## Verification utilities for typestate checking.
##
## Provides:
##
## - Compile-time proc registration for validation
## - `verifyTypestates()` macro for in-module verification
## - CLI tool support for full-project verification

import std/[macros, options, os, sets, strformat, strutils, tables]
import types, registry

type
  ProcKind* = enum
    ## Classification of procs operating on state types.
    pkTransition ## Marked with `{.transition.}`
    pkDestructorTransition ## Marked with `{.destructorTransition.}` (v0.9.0)
    pkNotATransition ## Marked with `{.notATransition.}`
    pkUnmarked ## No pragma specified

  RegisteredProc* = object
    ## Information about a proc registered for verification.
    ##
    ## :var name: The proc name
    ## :var sourceState: The first parameter's state type
    ## :var destStates: Return type state(s)
    ## :var kind: How the proc is marked
    ## :var declaredAt: Source location
    ## :var modulePath: Module where declared
    ## :var firstParamType: AST of the first parameter's type (preserves
    ##   modifiers like `sink`, `var`, `ref`, `ptr` for F5 decoy emission)
    ## :var extraParams: Trailing formal-parameter IdentDefs (params 2..N)
    ##   captured verbatim so F5 decoys reproduce the full signature,
    ##   matching overload resolution at call sites with extra args
    ## :var body: AST of the proc body, captured for later CFG analyzer use
    ##   (v0.9.0 destructor-transition validation). Defaults to
    ##   `newEmptyNode()` for procs that do not require body inspection.
    ## :var skipCfg: When `true`, suppresses CFG analysis for this proc
    ##   (v0.9.0 `{.skipCfgAnalysis.}` marker). Defaults to `false`.
    ## :var attachedObjectTypeName: Optional object type name for §3.7
    ##   typestate-attachment registry lookup (v0.9.0). `none` for procs
    ##   that are not attached to an object type.
    name*: string
    sourceState*: string
    destStates*: seq[string]
    kind*: ProcKind
    declaredAt*: LineInfo
    modulePath*: string
    firstParamType*: NimNode
    extraParams*: seq[NimNode]
    body*: NimNode
    skipCfg*: bool
    attachedObjectTypeName*: Option[string]

var registeredProcs* {.compileTime.}: seq[RegisteredProc]
  ## Compile-time list of all procs registered for verification.

proc registerProc*(info: RegisteredProc) {.compileTime.} =
  ## Register a proc for later verification.
  ##
  ## :param info: The proc information to register
  registeredProcs.add info

## --------------------------------------------------------------------------
## CFG analyzer (v0.9.0 §3.3)
##
## A compile-time walk over each registered proc body that validates
## typestate-bearing locals reach a terminal state (or are auto-consumed
## via a registered `{.destructorTransition.}`) at every exit edge of the
## proc: explicit return, raise, branch join, loop escape, fall-through.
##
## See `design-destructortransition-cfg-analyzer-20260516.md §3.3` and
## Appendix B for the full algorithm and diagnostic catalog.
## --------------------------------------------------------------------------

type
  LocalTypestate* = object
    ## Tracks one typestate-bearing local through the analyzer's walk.
    ##
    ## :var name: Local variable name (for diagnostics)
    ## :var stateType: Current state type's base name; advances as the
    ##   analyzer recognizes transition-consuming calls
    ## :var graph: Owning typestate
    ## :var declaredAt: Source location of the binding (for diagnostics)
    name*: string
    stateType*: string
    graph*: TypestateGraph
    declaredAt*: LineInfo

  LiveState* = object
    ## Analyzer state at a program point. `reachable=false` after an
    ## unconditional exit (return/raise) — subsequent statements in the
    ## same straight-line block are dead and emit no diagnostics.
    locals*: seq[LocalTypestate]
    reachable*: bool

proc initLiveState*(): LiveState {.compileTime.} =
  LiveState(locals: @[], reachable: true)

proc unreachableState*(): LiveState {.compileTime.} =
  LiveState(locals: @[], reachable: false)

proc buildDestructorTypes(): Table[string, TypestateGraph] {.compileTime.} =
  ## §3.3 Phase A: build the lookup table keyed on the type name the
  ## analyzer will see at a local's declaration site.
  ##
  ## - Path (a), state-typed param: key = `extractBaseName(sourceState)`.
  ## - Path (b), attached-object param: key = `attachedObjectTypeName.get`,
  ##   NOT the state name (which is the typestate STATE, not the holder).
  ##   Keying on the state name would miss the destructor and falsely flag
  ##   the local as not reaching terminal.
  ##
  ## Both keys insert into the same table — they cannot collide because
  ## path (a)'s key is a state type and path (b)'s key is an object type;
  ## the analyzer's per-local lookup is by the local's declared type's base
  ## name, which uniquely identifies which path applies.
  result = initTable[string, TypestateGraph]()
  for procInfo in registeredProcs:
    if procInfo.kind != pkDestructorTransition:
      continue
    let graphOpt = findTypestateForState(procInfo.sourceState)
    if graphOpt.isNone:
      continue
    let key =
      if procInfo.attachedObjectTypeName.isSome:
        procInfo.attachedObjectTypeName.get
      else:
        extractBaseName(procInfo.sourceState)
    result[key] = graphOpt.get

proc lookupTypestateForType*(
    typeName: string, destructorTypes: Table[string, TypestateGraph]
): Option[TypestateGraph] {.compileTime.} =
  ## Resolve a declared-type name to its typestate graph. Used by the
  ## analyzer when binding a local (e.g., `var x: Alive` -> Alive's graph).
  ##
  ## Two resolution paths, in order:
  ##
  ## 1. Direct state lookup: the declared type IS a state of some typestate
  ##    (path (a) — `var x: Alive` where Alive is a state). Uses
  ##    `findTypestateForState`.
  ##
  ## 2. Attached-object lookup: the declared type is an object type bound
  ##    to a typestate via the §3.7 attachment pragma (path (b) — `var
  ##    scope: PinnedScope[...]` where PinnedScope is attached). Uses
  ##    `findAttachmentForType`.
  ##
  ## The `destructorTypes` table is consulted as a hint but not the only
  ## source — a local of a typestate state without a registered destructor
  ## still binds and is tracked; the analyzer's exit-edge check rejects it
  ## if it never reaches terminal AND has no destructor.
  let base = extractBaseName(typeName)
  let direct = findTypestateForState(base)
  if direct.isSome:
    return direct
  let attached = findAttachmentForType(base)
  if attached.isSome and attached.get.typestateName in typestateRegistry:
    return some(typestateRegistry[attached.get.typestateName])
  return none(TypestateGraph)

proc extractTypeNameAst(node: NimNode): string {.compileTime.} =
  ## Extract a stable type-name string from an IdentDefs type slot.
  ## Handles `T`, `T[U, V]`, `var T`, `ref T`, `ptr T`, and qualified
  ## `module.T`. Returns the empty string if no name can be recovered.
  if node.isNil or node.kind == nnkEmpty:
    return ""
  case node.kind
  of nnkIdent, nnkSym:
    return node.strVal
  of nnkBracketExpr:
    if node.len >= 1:
      return extractTypeNameAst(node[0])
    return ""
  of nnkVarTy, nnkRefTy, nnkPtrTy:
    if node.len >= 1:
      return extractTypeNameAst(node[0])
    return ""
  of nnkDotExpr:
    # module.T -> T (extractBaseName handles trailing qualification, but
    # we'd rather strip here to keep the key stable across import paths)
    if node.len >= 2:
      return extractTypeNameAst(node[1])
    return ""
  else:
    return ""

proc findLocalInnermost*(state: LiveState, name: string): int {.compileTime.} =
  ## Find the index of the innermost (most-recently-bound) local with the
  ## given name. Returns -1 if no match. Iterates the locals sequence in
  ## reverse so that an inner-scope shadow takes precedence over an outer
  ## binding with the same identifier — required for correctness under
  ## identifier shadowing (§3.3, Finding #3).
  for i in countdown(state.locals.len - 1, 0):
    if state.locals[i].name == name:
      return i
  return -1

proc isTerminalForGraph*(
    stateType: string, graph: TypestateGraph
): bool {.compileTime.} =
  ## Return `true` if `stateType` (a base name) is one of the typestate's
  ## terminal states.
  for term in graph.terminalStates:
    if extractBaseName(term) == stateType:
      return true
  return false

proc hasDestructorFor*(
    local: LocalTypestate, destructorTypes: Table[string, TypestateGraph]
): bool {.compileTime.} =
  ## Return `true` if a `{.destructorTransition.}` is registered for this
  ## local's current declared state type AND keyed to the local's owning
  ## typestate graph (path (a) — state-typed param).
  local.stateType in destructorTypes and
    destructorTypes[local.stateType].name == local.graph.name

proc extractCalleeName*(call: NimNode): string {.compileTime.} =
  ## Extract a stable callee name from a `nnkCall` / `nnkCommand` node.
  ## Returns the empty string when the callee is not a simple identifier
  ## (e.g. `obj.method(...)`, `(expr)(...)`, generic instantiations).
  if call.len < 1:
    return ""
  let head = call[0]
  case head.kind
  of nnkIdent, nnkSym:
    return head.strVal
  of nnkOpenSymChoice, nnkClosedSymChoice:
    # Symbol choice — every entry shares the same name.
    if head.len >= 1 and head[0].kind in {nnkIdent, nnkSym}:
      return head[0].strVal
    return ""
  of nnkBracketExpr:
    # Generic instantiation: foo[T](...) — head[0] is the proc name.
    if head.len >= 1 and head[0].kind in {nnkIdent, nnkSym}:
      return head[0].strVal
    return ""
  of nnkDotExpr:
    # Qualified call: module.foo(...) — take the trailing identifier.
    if head.len >= 2 and head[1].kind in {nnkIdent, nnkSym}:
      return head[1].strVal
    return ""
  else:
    return ""

proc findRegisteredTransitionForArg*(
    callName: string, argStateType: string, argGraphName: string
): Option[RegisteredProc] {.compileTime.} =
  ## Look up a registered `pkTransition` or `pkDestructorTransition` proc
  ## by name whose `sourceState` (base name) matches `argStateType` and
  ## whose typestate matches the local's owning graph. Returns `none` if
  ## no overload matches.
  ##
  ## Handles the union-source convention: a registered proc with empty
  ## `sourceState` covers multiple source states; the union case is not
  ## resolved here (the analyzer treats it as a non-match for per-arg
  ## advancement, since the dst is the same for the union but the analyzer
  ## has no per-source information). Single-source overloads are the
  ## common shape and are what these fixtures exercise.
  ##
  ## Iterates reverse so the most recently registered overload wins
  ## under any duplicate registration — defensive consistency with
  ## innermost-first shadowing.
  for i in countdown(registeredProcs.len - 1, 0):
    let p = registeredProcs[i]
    if p.kind notin {pkTransition, pkDestructorTransition}:
      continue
    if p.name != callName:
      continue
    if p.sourceState.len == 0:
      # Union-source proc — without explicit per-source info we cannot
      # decide which destination this call lands on. Skip.
      continue
    if extractBaseName(p.sourceState) != argStateType:
      continue
    let graphOpt = findTypestateForState(p.sourceState)
    if graphOpt.isNone:
      continue
    if graphOpt.get.name != argGraphName:
      continue
    return some(p)
  return none(RegisteredProc)

proc firstParamConsumes*(p: RegisteredProc): bool {.compileTime.} =
  ## Heuristic: does this registered proc consume its first parameter?
  ## Returns `true` when the first-param-type AST has a `sink` modifier
  ## (Nim sink-param shape: `nnkCommand(sink, T)`), or otherwise when
  ## the proc's kind is `pkDestructorTransition` (always consuming via
  ## `=destroy` injection — its formal param is `var T`, semantically
  ## a sink at the analyzer level).
  ##
  ## Non-sink, non-destructor procs that take a typestate-bearing arg
  ## (e.g., `var T` for in-place mutation, or `T` by value with
  ## `consumeOnTransition = false`) leave the caller's local accessible
  ## after the call; the analyzer advances the local's state in place
  ## rather than dropping it.
  if p.kind == pkDestructorTransition:
    return true
  let typ = p.firstParamType
  if typ.isNil:
    return false
  if typ.kind == nnkCommand and typ.len == 2 and typ[0].kind in {nnkIdent, nnkSym} and
      typ[0].strVal == "sink":
    return true
  return false

proc applyCallTransitions*(
    state: var LiveState, call: NimNode, destructorTypes: Table[string, TypestateGraph]
) {.compileTime.} =
  ## Inspect a `nnkCall` / `nnkCommand` node. For each argument that is
  ## a bare identifier referencing a tracked local, look up a registered
  ## transition proc by name and matching source state; if found, advance
  ## the local's state to the registered destination. If the new state is
  ## terminal, drop the local from tracking (consumed).
  ##
  ## v0.9.0 Finding #1 (a/c/d): tracks transitions through `nnkCall`,
  ## `nnkCommand`, and (via callers) `nnkLet/VarSection` / `nnkAsgn` RHS
  ## composition. Sink-consume composes naturally: a `consume(g)` call
  ## drops `g` from tracking; the enclosing binding then receives the
  ## registered destination.
  if call.kind notin {nnkCall, nnkCommand}:
    return
  let callName = extractCalleeName(call)
  if callName.len == 0:
    return
  for argIdx in 1 ..< call.len:
    let arg = call[argIdx]
    var argIdent: string
    case arg.kind
    of nnkIdent, nnkSym:
      argIdent = arg.strVal
    of nnkCommand:
      # `move x`, `sink x` — peel a single modifier ident.
      if arg.len == 2 and arg[0].kind in {nnkIdent, nnkSym} and
          arg[1].kind in {nnkIdent, nnkSym}:
        let modName = arg[0].strVal
        if modName in ["move", "sink"]:
          argIdent = arg[1].strVal
      if argIdent.len == 0:
        continue
    else:
      continue
    let localIdx = findLocalInnermost(state, argIdent)
    if localIdx < 0:
      continue
    let local = state.locals[localIdx]
    let txOpt =
      findRegisteredTransitionForArg(callName, local.stateType, local.graph.name)
    if txOpt.isNone:
      continue
    let tx = txOpt.get
    let consumes = firstParamConsumes(tx)
    # Sink/destructor-consuming call: the argument local is no longer
    # accessible after the call. The "new state" (the call's destination)
    # is the call's RETURN value, not a mutation of the argument — so
    # drop the argument local from tracking regardless of dst-terminal.
    if consumes:
      state.locals.delete(localIdx)
      continue
    # Non-consuming call (var T / value T with consumeOnTransition=false):
    # the local persists at the call site; advance its tracked state in
    # place. Branching destinations cannot be resolved per-call without
    # a wrapping `match` statement; treat as terminal-equivalent and drop.
    if tx.destStates.len == 0:
      state.locals.delete(localIdx)
      continue
    if tx.destStates.len > 1:
      state.locals.delete(localIdx)
      continue
    let dstBase = extractBaseName(tx.destStates[0])
    if isTerminalForGraph(dstBase, local.graph):
      state.locals.delete(localIdx)
    else:
      state.locals[localIdx] = LocalTypestate(
        name: local.name,
        stateType: dstBase,
        graph: local.graph,
        declaredAt: local.declaredAt,
      )

proc tryBindLocalFromCallInit*(
    state: var LiveState,
    nameNode: NimNode,
    initNode: NimNode,
    destructorTypes: Table[string, TypestateGraph],
) {.compileTime.} =
  ## Bind a single-name local introduced by `var/let name = call(...)` to
  ## the call's registered destination state, when the RHS is a registered
  ## transition call that produces a typestate-bearing value. Composes
  ## with `applyCallTransitions` already having been invoked on the RHS
  ## (which advances or drops tracked locals passed as arguments).
  ##
  ## This handles the sink-consume shape `let f = consume(g)` and the
  ## init-via-call shape `var f = open()`: in both cases the LHS binds to
  ## the registered destination of the call's transition. The destination
  ## may be terminal — in which case we bind tracking briefly so downstream
  ## exit edges see it (validateExitEdge accepts terminals).
  if initNode.isNil or initNode.kind notin {nnkCall, nnkCommand}:
    return
  let callName = extractCalleeName(initNode)
  if callName.len == 0:
    return
  # Resolve registered transition with ANY source state matching name; we
  # need its dest. If sourceState matches a tracked-arg's state, the call's
  # arg was already advanced by applyCallTransitions; we just bind LHS.
  for i in countdown(registeredProcs.len - 1, 0):
    let p = registeredProcs[i]
    if p.kind notin {pkTransition, pkDestructorTransition}:
      continue
    if p.name != callName:
      continue
    if p.destStates.len != 1:
      continue
    let dstBase = extractBaseName(p.destStates[0])
    let graphOpt = findTypestateForState(p.destStates[0])
    if graphOpt.isNone:
      continue
    var localName: string
    case nameNode.kind
    of nnkIdent, nnkSym:
      localName = nameNode.strVal
    of nnkPostfix:
      if nameNode.len >= 2 and nameNode[1].kind in {nnkIdent, nnkSym}:
        localName = nameNode[1].strVal
      else:
        return
    of nnkPragmaExpr:
      if nameNode.len >= 1 and nameNode[0].kind in {nnkIdent, nnkSym}:
        localName = nameNode[0].strVal
      else:
        return
    else:
      return
    state.locals.add LocalTypestate(
      name: localName,
      stateType: dstBase,
      graph: graphOpt.get,
      declaredAt: nameNode.lineInfoObj,
    )
    return

proc bindLocalsFromIdentDefs(
    state: var LiveState,
    identDefs: NimNode,
    destructorTypes: Table[string, TypestateGraph],
) {.compileTime.} =
  ## For each name in an `nnkIdentDefs` (var/let section entry), if the
  ## declared type resolves to a typestate, push a `LocalTypestate` onto
  ## the live-set with `stateType = extractBaseName(declaredType)`.
  ##
  ## IdentDefs shape: `name1, name2, ..., type, defaultValueOrEmpty`.
  if identDefs.len < 3:
    return
  let typeSlot = identDefs[identDefs.len - 2]
  let initSlot = identDefs[identDefs.len - 1]
  let typeName = extractTypeNameAst(typeSlot)
  if typeName.len == 0:
    # No declared type: try the call-init shape `var name = call(...)`.
    # Apply the call's transition effects to any tracked args first, then
    # bind the LHS to the call's registered destination. Each leading name
    # in the IdentDefs is bound (Nim allows grouped names in a single
    # IdentDefs only when they share a type slot — a typeless init with
    # grouped names is rare but supported defensively).
    if initSlot.kind in {nnkCall, nnkCommand}:
      applyCallTransitions(state, initSlot, destructorTypes)
      for i in 0 ..< identDefs.len - 2:
        tryBindLocalFromCallInit(state, identDefs[i], initSlot, destructorTypes)
    return
  let graphOpt = lookupTypestateForType(typeName, destructorTypes)
  if graphOpt.isNone:
    # Type is not a registered typestate state. Still apply call-init
    # transitions so any sink-consumed argument is dropped from tracking
    # — the LHS local is non-typestated, so no LHS binding needed.
    if initSlot.kind in {nnkCall, nnkCommand}:
      applyCallTransitions(state, initSlot, destructorTypes)
    return
  let graph = graphOpt.get
  let stateType = extractBaseName(typeName)
  # Apply transition effects from any RHS call before binding the LHS, so
  # tracked-arg locals are advanced/dropped in the right order.
  if initSlot.kind in {nnkCall, nnkCommand}:
    applyCallTransitions(state, initSlot, destructorTypes)
  for i in 0 ..< identDefs.len - 2:
    let nameNode = identDefs[i]
    var localName: string
    case nameNode.kind
    of nnkIdent, nnkSym:
      localName = nameNode.strVal
    of nnkPostfix:
      # exported `name*`: take the leaf
      if nameNode.len >= 2 and nameNode[1].kind in {nnkIdent, nnkSym}:
        localName = nameNode[1].strVal
      else:
        continue
    of nnkPragmaExpr:
      # `name {.pragma.}`: take the leading name
      if nameNode.len >= 1 and nameNode[0].kind in {nnkIdent, nnkSym}:
        localName = nameNode[0].strVal
      else:
        continue
    else:
      continue
    state.locals.add LocalTypestate(
      name: localName,
      stateType: stateType,
      graph: graph,
      declaredAt: identDefs.lineInfoObj,
    )

proc validateExitEdge*(
    state: LiveState,
    node: NimNode,
    edgeKind: string,
    destructorTypes: Table[string, TypestateGraph],
) {.compileTime.} =
  ## §3.3 core rejection (CFG-001): at every exit edge, each tracked local
  ## must EITHER be in a terminal state OR have a registered
  ## `{.destructorTransition.}` for its current type (which guarantees Nim's
  ## `=destroy` injection will fire the bridging transition).
  if not state.reachable:
    return
  for local in state.locals:
    if isTerminalForGraph(local.stateType, local.graph):
      continue
    # Destructor recognition: the local's declared type's base name keys
    # the destructorTypes table. Match BOTH the type name (path (a) — state-
    # typed) and the attached object name (path (b)). For step 1 we only
    # have stateType (the *current* state); attached-object locals would
    # need an extra `declaredType` field — deferred until binding wires it.
    if hasDestructorFor(local, destructorTypes):
      continue
    let terminalList = local.graph.terminalStates.join(", ")
    error(
      "Typestate-bearing local '" & local.name &
        "' has not reached a terminal state at this " & edgeKind & ". Current state: '" &
        local.stateType & "' in typestate '" & local.graph.name & "'. Terminal states: [" &
        terminalList & "]. Either advance the local to a terminal state before " &
        edgeKind & ", or arrange for a `{.destructorTransition.}` to fire (held by an" &
        " object whose `=destroy` performs the transition).",
      node,
    )

proc reconcileBranches*(
    branchStates: seq[LiveState], hasElse: bool, entry: LiveState, node: NimNode
): LiveState {.compileTime.} =
  ## §3.3 branch reconciliation (CFG-002): merge per-branch LiveStates at a
  ## join point.
  ##
  ## - If `hasElse=false`, an implicit branch carrying `entry` unchanged is
  ##   added (fall-through with no rebinding).
  ## - Unreachable branches (`reachable=false` because they exit) contribute
  ##   nothing to the merge.
  ## - For each local appearing in every reachable branch, all branches must
  ##   agree on the post-state OR each branch must reach a terminal state
  ##   (possibly different terminals — the local has reached *a* terminal).
  ## - For each entry-set local: if it is consumed (absent) in some branches
  ##   but remains non-terminal in others, CFG-002 fires (Finding #2). An
  ##   "absent" entry-local in a reachable branch means that branch consumed
  ##   it via a terminal-discard or a registered terminal-producing call.
  ##   Inconsistent consumption is rejected.
  ## - State-divergence at the join point emits CFG-002 keyed on the node.
  var effective: seq[LiveState] = @[]
  for s in branchStates:
    if s.reachable:
      effective.add s
  if not hasElse:
    effective.add entry

  if effective.len == 0:
    # All branches exited. The join point is itself unreachable.
    return unreachableState()

  result = LiveState(locals: @[], reachable: true)

  # First pass: entry-set locals. For each local present in `entry`, check
  # its state across all effective branches. A branch that lacks the local
  # has consumed it (terminal-discard / terminal-producing call), which the
  # analyzer treats as "reached terminal in this branch."
  var entryLocalNames: HashSet[string]
  for el in entry.locals:
    entryLocalNames.incl el.name
    var presentStates: seq[string] = @[]
    var absentBranches = 0
    for b in effective:
      let idx = findLocalInnermost(b, el.name)
      if idx < 0:
        absentBranches.inc
      else:
        presentStates.add b.locals[idx].stateType
    let totalBranches = effective.len

    if presentStates.len == 0:
      # Consumed in every branch — drop from merge.
      continue

    # Some branches still hold the local. Check terminal-vs-non-terminal.
    var allPresentTerminal = true
    var anyPresentNonTerminal = false
    for s in presentStates:
      if isTerminalForGraph(s, el.graph):
        discard
      else:
        allPresentTerminal = false
        anyPresentNonTerminal = true

    if absentBranches > 0 and anyPresentNonTerminal:
      # NEW (Finding #2): inconsistent consumption — some branches reached
      # terminal (absent), others left the local non-terminal.
      let stateList = presentStates.join(", ")
      error(
        "Typestate-bearing local '" & el.name &
          "' has inconsistent state across branches: [" & stateList & "] in " &
          $presentStates.len & " of " & $totalBranches &
          " branches, consumed in the remaining " & $absentBranches &
          " branch(es); merge point requires all branches to reach the same" &
          " state or a common terminal.",
        node,
      )

    # All present branches agree on a single state?
    var allSame = true
    for s in presentStates[1 ..^ 1]:
      if s != presentStates[0]:
        allSame = false
        break

    if allSame and absentBranches == 0:
      result.locals.add LocalTypestate(
        name: el.name,
        stateType: presentStates[0],
        graph: el.graph,
        declaredAt: el.declaredAt,
      )
      continue

    if allPresentTerminal:
      # Every present branch reached a terminal (possibly different
      # terminals); absent branches consumed terminally. Downstream exit
      # edges accept any terminal — keep a terminal witness if any branch
      # still holds the local.
      result.locals.add LocalTypestate(
        name: el.name,
        stateType: presentStates[0],
        graph: el.graph,
        declaredAt: el.declaredAt,
      )
      continue

    # Different per-branch non-terminal states with no absent branches.
    # Falls under the existing CFG-002 divergence rule.
    error(
      "Typestate-bearing local '" & el.name &
        "' has inconsistent state across branches: [" & presentStates.join(", ") &
        "]; merge point requires all branches to reach the same state or" &
        " a common terminal.",
      node,
    )

  # Second pass: branch-introduced locals (declared inside one or more
  # branches, NOT in entry). Iterate the union across effective branches
  # so a local introduced in any branch is considered. For each such local:
  # - If only ONE branch declares it, it's scope-local — drop.
  # - If MULTIPLE branches declare it with the same state — keep that state.
  # - If MULTIPLE branches declare it with different states — CFG-002 (or
  #   terminal-union exception).
  # This preserves the pre-existing `cfg_analyzer_if_branches_diverge.nim`
  # behavior where both arms declare `var s: <state>` with different types.
  var seenBranchLocals: HashSet[string]
  for b in effective:
    for local in b.locals:
      if local.name in entryLocalNames:
        continue
      if local.name in seenBranchLocals:
        continue
      seenBranchLocals.incl local.name
      var perBranch: seq[string] = @[]
      for b2 in effective:
        let idx = findLocalInnermost(b2, local.name)
        if idx >= 0:
          perBranch.add b2.locals[idx].stateType
      if perBranch.len <= 1:
        # Only declared in one branch — scope-local; do not propagate.
        continue
      var allSame = true
      for s in perBranch[1 ..^ 1]:
        if s != perBranch[0]:
          allSame = false
          break
      if allSame:
        result.locals.add LocalTypestate(
          name: local.name,
          stateType: perBranch[0],
          graph: local.graph,
          declaredAt: local.declaredAt,
        )
        continue
      var allTerminal = true
      for s in perBranch:
        if not isTerminalForGraph(s, local.graph):
          allTerminal = false
          break
      if allTerminal:
        result.locals.add LocalTypestate(
          name: local.name,
          stateType: perBranch[0],
          graph: local.graph,
          declaredAt: local.declaredAt,
        )
        continue
      error(
        "Typestate-bearing local '" & local.name &
          "' has inconsistent state across branches: [" & perBranch.join(", ") &
          "]; merge point requires all branches to reach the same state or" &
          " a common terminal.",
        node,
      )

proc walkCfg(
    node: NimNode, state: LiveState, destructorTypes: Table[string, TypestateGraph]
): LiveState {.compileTime.} =
  ## §3.3 tree-traversal algorithm. Returns the LiveState at the program
  ## point AFTER `node`.
  ##
  ## v0.9.0 steps 2-4 cover: var/let bindings, return, raise, if, case,
  ## and fall-through (driven by the caller). Steps 5-8 extend this with
  ## try/except/finally, while/for, break/continue, discard, and transition
  ## recognition for in-state advancement.
  if node.isNil:
    return state
  result = state
  case node.kind
  of nnkStmtList, nnkStmtListExpr:
    for child in node:
      result = walkCfg(child, result, destructorTypes)
      if not result.reachable:
        # Statements after an unconditional exit are dead — stop walking
        # this block. The exit edge has already been validated by the
        # return/raise handler.
        break
  of nnkBlockStmt, nnkBlockExpr:
    # blockStmt is `block [label]: body`; body is the last child.
    if node.len >= 1:
      result = walkCfg(node[^1], result, destructorTypes)
  of nnkVarSection, nnkLetSection:
    for identDefs in node:
      if identDefs.kind == nnkIdentDefs:
        bindLocalsFromIdentDefs(result, identDefs, destructorTypes)
  of nnkIfStmt, nnkIfExpr:
    var branchStates: seq[LiveState] = @[]
    var hasElse = false
    for branch in node:
      case branch.kind
      of nnkElifBranch, nnkElifExpr:
        # branch: cond, body
        if branch.len >= 2:
          branchStates.add walkCfg(branch[1], result, destructorTypes)
      of nnkElse, nnkElseExpr:
        hasElse = true
        if branch.len >= 1:
          branchStates.add walkCfg(branch[0], result, destructorTypes)
      else:
        discard
    result = reconcileBranches(branchStates, hasElse, result, node)
  of nnkCaseStmt:
    # case node: selector, ofBranch..., (elseBranch)?
    var branchStates: seq[LiveState] = @[]
    var hasElse = false
    for i in 1 ..< node.len:
      let branch = node[i]
      case branch.kind
      of nnkOfBranch:
        # ofBranch: pattern(s)..., body
        if branch.len >= 1:
          branchStates.add walkCfg(branch[^1], result, destructorTypes)
      of nnkElifBranch:
        # case-with-guards: cond, body
        if branch.len >= 2:
          branchStates.add walkCfg(branch[1], result, destructorTypes)
      of nnkElse:
        hasElse = true
        if branch.len >= 1:
          branchStates.add walkCfg(branch[0], result, destructorTypes)
      else:
        discard
    result = reconcileBranches(branchStates, hasElse, result, node)
  of nnkReturnStmt:
    validateExitEdge(result, node, "return", destructorTypes)
    result = unreachableState()
  of nnkRaiseStmt:
    validateExitEdge(result, node, "raise", destructorTypes)
    result = unreachableState()
  of nnkDiscardStmt:
    # §3.3 handleDiscard (CFG-003): a `discard <expr>` whose expression has
    # a typestate-bearing static type is rejected when that type is NOT a
    # terminal state AND no `{.destructorTransition.}` covers it. Bare
    # `discard` (empty operand) is a no-op for the analyzer.
    #
    # Static-type resolution: in a macro pass at verifyTypestates() time the
    # body AST is captured pre-typecheck. R-6 fallback: we resolve the
    # discarded expression via the analyzer's per-local state map (when the
    # expression is a bare Ident/Sym referring to a tracked local). Other
    # shapes (call expressions, dotExprs) cannot be reliably typed without
    # `getTypeInst`, which is not callable here on un-typed AST — those are
    # passed through. Discarding a tracked local that has a registered
    # destructor is accepted (the destructor will bridge to terminal).
    if node.len >= 1 and node[0].kind != nnkEmpty:
      let opnd = node[0]
      # Recurse into the discarded expression so any nested registered call
      # has its transition effects applied to tracked args (e.g., `discard
      # close(f)` advances/consumes `f`).
      result = walkCfg(opnd, result, destructorTypes)
      var localIdx = -1
      var exprStateName = ""
      if opnd.kind in {nnkIdent, nnkSym}:
        # Innermost-first lookup so inner-scope shadows take precedence
        # over outer bindings (§3.3, Finding #3).
        localIdx = findLocalInnermost(result, opnd.strVal)
        if localIdx >= 0:
          exprStateName = result.locals[localIdx].stateType
      if exprStateName.len > 0:
        let graphOpt = findTypestateForState(exprStateName)
        if graphOpt.isSome:
          let graph = graphOpt.get
          let isTerminal = isTerminalForGraph(exprStateName, graph)
          let hasDestructor =
            exprStateName in destructorTypes and
            destructorTypes[exprStateName].name == graph.name
          if not isTerminal and not hasDestructor:
            let terminalList = graph.terminalStates.join(", ")
            error(
              "`discard` of typestate value of type '" & exprStateName &
                "' is not allowed: type is not a terminal state of typestate '" &
                graph.name & "'. Terminal states: [" & terminalList &
                "]. Hint: either complete the transition chain to a terminal" &
                " state, or remove the `discard` and consume the value" & " explicitly.",
              node,
            )
          elif isTerminal and localIdx >= 0:
            # Terminal-state discard: consume the specific local we
            # resolved by name (innermost-first), not the first matching
            # state-type which would mishandle shadowing.
            result.locals.delete(localIdx)
  of nnkWhileStmt, nnkForStmt:
    # §3.3 loop handling (conservative): walk the body once with the entry
    # state, then reconcile body-exit with entry (loop may execute 0 or N
    # times, like an if-without-else). This is intentionally pessimistic;
    # a full fixpoint iteration is deferred per design §3.3.
    #
    # nnkWhileStmt: (cond, body); nnkForStmt: (var..., iter, body).
    if node.len >= 1:
      let bodyEnd = walkCfg(node[^1], result, destructorTypes)
      result = reconcileBranches(@[bodyEnd], false, result, node)
  of nnkBreakStmt:
    # §3.3 break: an unconditional exit from the enclosing loop scope. Any
    # typestate-bearing local introduced inside the loop body that escapes
    # the loop via break (rather than completing the body to a terminal
    # state) must satisfy validateExitEdge at the break point. The loop
    # reconcile above only captures the body-end state, so a break that
    # bypasses the body's terminal-advancing path would otherwise escape
    # detection. Validating here makes that exit edge explicit.
    validateExitEdge(result, node, "break", destructorTypes)
    result = unreachableState()
  of nnkContinueStmt:
    # continue: jumps back to the loop header, NOT out of the loop. Locals
    # introduced inside the loop body remain in scope only for the current
    # iteration; the loop reconcile handles the next-iteration / fall-out
    # join. Treat as straight-line exit for the linear walk (statements
    # after continue are dead) but do NOT validateExitEdge — continue is
    # not a proc-level exit.
    result = unreachableState()
  of nnkTryStmt:
    # §3.3 try/except/finally — pessimistic per the design algorithm.
    #
    # Shape: nnkTryStmt(body, [exceptBranch...], [finally?]). The try body
    # is walked normally. Each except branch is walked with the ENTRY state
    # (most pessimistic — the raise may have fired before any state
    # advancement in the body, so we cannot trust body-end mutations to be
    # visible to the handlers). The finally body, when present, is walked
    # with the reconciled state of body-end + each except-end and runs on
    # every exit path.
    if node.len >= 1:
      let bodyEnd = walkCfg(node[0], result, destructorTypes)
      var exceptEnds: seq[LiveState] = @[]
      var hasFinally = false
      var finallyBody: NimNode = nil
      for i in 1 ..< node.len:
        let child = node[i]
        case child.kind
        of nnkExceptBranch:
          # Pessimistic: enter except with the pre-try entry state, not bodyEnd.
          exceptEnds.add walkCfg(child[^1], result, destructorTypes)
        of nnkFinally:
          hasFinally = true
          if child.len >= 1:
            finallyBody = child[0]
        else:
          discard
      let postCatch = reconcileBranches(@[bodyEnd] & exceptEnds, true, result, node)
      if hasFinally and finallyBody != nil:
        result = walkCfg(finallyBody, postCatch, destructorTypes)
      else:
        result = postCatch
  of nnkCall, nnkCommand:
    # §3.3 transition-call recognition (Finding #1, scope (a)). For each
    # tracked local passed as an argument to a registered transition proc
    # whose source state matches the local's current state, advance the
    # local to the registered destination (or drop on terminal /
    # branching destination).
    applyCallTransitions(result, node, destructorTypes)
  of nnkAsgn:
    # §3.3 transition-asgn recognition (Finding #1, scope (c)). Shape:
    # nnkAsgn(lhs, rhs). When the RHS is a registered transition call:
    #   1. Apply the call's transition to any tracked argument first.
    #   2. If the LHS is a bare identifier referencing a tracked local,
    #      update that local's state to the call's registered destination
    #      (or drop on terminal destination).
    # If the RHS is not a registered call, recurse into children so any
    # deeper call is still recognized.
    if node.len >= 2:
      let lhs = node[0]
      let rhs = node[1]
      if rhs.kind in {nnkCall, nnkCommand}:
        applyCallTransitions(result, rhs, destructorTypes)
        let callName = extractCalleeName(rhs)
        if callName.len > 0 and lhs.kind in {nnkIdent, nnkSym}:
          let lhsIdx = findLocalInnermost(result, lhs.strVal)
          # Find a registered transition proc with this name producing a
          # single typestate destination — innermost-first for overload
          # resolution consistency.
          var tx: Option[RegisteredProc]
          for i in countdown(registeredProcs.len - 1, 0):
            let p = registeredProcs[i]
            if p.kind notin {pkTransition, pkDestructorTransition}:
              continue
            if p.name != callName:
              continue
            if p.destStates.len != 1:
              continue
            tx = some(p)
            break
          if tx.isSome:
            let dstBase = extractBaseName(tx.get.destStates[0])
            let graphOpt = findTypestateForState(tx.get.destStates[0])
            if graphOpt.isSome:
              let graph = graphOpt.get
              if lhsIdx >= 0:
                # Re-binding an existing tracked local. If destination is
                # terminal, drop the old tracking (consumed at this asgn);
                # otherwise update its state to the new dst.
                if isTerminalForGraph(dstBase, graph):
                  result.locals.delete(lhsIdx)
                else:
                  result.locals[lhsIdx] = LocalTypestate(
                    name: lhs.strVal,
                    stateType: dstBase,
                    graph: graph,
                    declaredAt: lhs.lineInfoObj,
                  )
              else:
                # First binding of this name as a typestate-bearing local.
                if not isTerminalForGraph(dstBase, graph):
                  result.locals.add LocalTypestate(
                    name: lhs.strVal,
                    stateType: dstBase,
                    graph: graph,
                    declaredAt: lhs.lineInfoObj,
                  )
      else:
        # Non-call RHS — recurse into children to catch nested calls.
        for child in node:
          result = walkCfg(child, result, destructorTypes)
          if not result.reachable:
            break
  else:
    # Default: recurse into children. Catches nested expressions whose
    # transition-bearing calls live inside larger AST shapes (e.g., a
    # call wrapped in a `result = ...` assignment, or a parenthesized
    # expression). Each recursive walk applies transition effects via
    # the nnkCall/nnkCommand handler.
    for child in node:
      result = walkCfg(child, result, destructorTypes)
      if not result.reachable:
        break

proc procHasSkipCfgPragma(procInfo: RegisteredProc): bool {.compileTime.} =
  ## v0.9.0 step 1: respect the `skipCfg` field set by pragmas.nim. Step 8
  ## adds the full `{.skipCfgAnalysis.}` semantics; for now we honor whatever
  ## the registration captured.
  procInfo.skipCfg

proc runCfgAnalyzer*() {.compileTime.} =
  ## Entry point for the v0.9.0 CFG analyzer (§3.3). Iterates every proc in
  ## `registeredProcs` and walks its captured body AST, validating exit
  ## edges against the live-set of typestate-bearing locals.
  ##
  ## Phase A (table build) runs once per call; Phase B (per-proc walk) runs
  ## once per registered proc. Procs without a captured body (`body` is
  ## empty) are skipped — they were registered before the body-capture
  ## extension or are CLI-tooling registrations that do not need analysis.
  let destructorTypes = buildDestructorTypes()
  for procInfo in registeredProcs:
    if procHasSkipCfgPragma(procInfo):
      continue
    if procInfo.body.isNil or procInfo.body.kind == nnkEmpty:
      continue
    var state = initLiveState()
    let endState = walkCfg(procInfo.body, state, destructorTypes)
    # Fall-through exit edge: implicit return at end of body, only if still
    # reachable (i.e., body did not end in an unconditional return/raise).
    if endState.reachable:
      validateExitEdge(endState, procInfo.body, "fall-through", destructorTypes)

macro verifyTypestates*(): untyped =
  ## Verify all registered typestates and procs.
  ##
  ## Call at the end of a module to check:
  ##
  ## - All transitions are valid
  ## - All procs on state types are properly marked (if strictTransitions)
  ## - No external transitions on sealed typestates
  ##
  ## Example:
  ##
  ## ```nim
  ## import typestates
  ##
  ## typestate File:
  ##   states Closed, Open
  ##   transitions:
  ##     Closed -> Open
  ##
  ## proc open(f: Closed): Open {.transition.} = ...
  ##
  ## verifyTypestates()  # Validates everything above
  ## ```
  ##
  ## :returns: Empty statement list (validation is compile-time only)
  ## :raises: Compile-time error if verification fails

  result = newStmtList()

  # Check each registered proc
  for procInfo in registeredProcs:
    if procInfo.kind == pkUnmarked:
      # Find the typestate for this state
      let graphOpt = findTypestateForState(procInfo.sourceState)
      if graphOpt.isSome:
        let graph = graphOpt.get

        # Check strictTransitions
        if graph.strictTransitions:
          error(
            fmt"""Unmarked proc '{procInfo.name}' operates on state '{procInfo.sourceState}'.
  Typestate '{graph.name}' has strictTransitions = true.
  Add {{.transition.}} or {{.notATransition.}} pragma.
  Declared at: {procInfo.declaredAt}"""
          )

        # Check for external procs
        if procInfo.modulePath != graph.declaredInModule:
          error(
            fmt"""Unmarked proc '{procInfo.name}' on typestate '{graph.name}' from external module.
  External modules must use {{.notATransition.}} for procs on typestate states.
  Declared at: {procInfo.declaredAt}"""
          )

  # F5: emit state-aware error decoy procs for transitions in this module.
  #
  # For each (procName, typestate) pair in `registeredProcs`, build the set
  # of source states already covered by a real `{.transition.}` overload.
  # For every OTHER state in that typestate, emit a `{.error: "...".}` decoy
  # so calling the proc on the wrong source state fires a tailored compile
  # error instead of the generic "type mismatch" diagnostic.
  #
  # v0.5 scope (intentional skips):
  #   - Generic typestates (`graph.typeParams.len > 0`): codegen extension
  #     deferred to v0.6 (see CHANGELOG).
  #   - Branching-return procs (`destStates.len > 1`): deferred to v0.6.
  #   - Union-source procs (registered with `sourceState == ""`): the proc
  #     covers multiple source states; treat each covered state as a real
  #     overload but do not emit a decoy keyed off the union.
  #   - External-module procs: cannot exist for `{.transition.}` (validated
  #     in pragmas.nim), but defensively skipped here too.
  type
    TransitionKey = tuple[name: string, typestateName: string]
    TransitionInfo = object
      name: string
      typestate: TypestateGraph
      coveredSources: seq[string]
      destStates: seq[string]
      modulePath: string
      firstParamType: NimNode # AST of the first param type (any source state)
      extraParams: seq[NimNode] # Trailing IdentDefs from the registered overload
      anySkipped: bool # any overload of this name was generic / branching / union

  var groups: Table[TransitionKey, TransitionInfo]
  # Track union-source proc names so the second pass can flag matching
  # groups in O(N+M) instead of O(N*M).
  var unionProcNames: HashSet[string]

  for procInfo in registeredProcs:
    if procInfo.kind != pkTransition:
      continue
    if procInfo.sourceState.len == 0:
      # Union-source proc: defer the entire group (v0.5). Track the name so
      # the second pass below can flag any same-named non-union overloads.
      unionProcNames.incl procInfo.name
      continue
    let graphOpt = findTypestateForState(procInfo.sourceState)
    if graphOpt.isNone:
      continue
    let graph = graphOpt.get
    if procInfo.modulePath != graph.declaredInModule:
      continue
    let key: TransitionKey = (name: procInfo.name, typestateName: graph.name)
    if key notin groups:
      groups[key] = TransitionInfo(
        name: procInfo.name,
        typestate: graph,
        coveredSources: @[],
        destStates: procInfo.destStates,
        modulePath: procInfo.modulePath,
        firstParamType: procInfo.firstParamType,
        extraParams: procInfo.extraParams,
        anySkipped: false,
      )
    # NOTE: Nim's `tables.[]` has a `var T` overload, so writes through
    # `groups[key].field = ...` mutate the entry in place.
    if procInfo.sourceState notin groups[key].coveredSources:
      groups[key].coveredSources.add procInfo.sourceState
    # If overloads disagree on extra params or destination, the decoy can't
    # represent both signatures; mark the group skipped to avoid a partial
    # decoy that wouldn't catch every misuse cleanly.
    if procInfo.extraParams.len != groups[key].extraParams.len:
      groups[key].anySkipped = true
    if procInfo.destStates.len != 1:
      groups[key].anySkipped = true

  # Flag groups with a union-source overload as skipped. O(N+M) via the
  # name-set collected above.
  for key, info in groups.mpairs:
    if key.name in unionProcNames:
      info.anySkipped = true

  # Helper: produce a new first-param type AST that preserves the original
  # modifier shape (sink T, var T, ref T, ptr T, plain T) but swaps the
  # leaf type ident for the new state ident.
  proc replaceLeafState(node: NimNode, newIdent: NimNode): NimNode =
    case node.kind
    of nnkIdent, nnkSym:
      result = newIdent
    of nnkCommand:
      if node.len == 2 and node[0].kind == nnkIdent and node[0].strVal == "sink":
        result = nnkCommand.newTree(node[0].copyNimTree, newIdent)
      else:
        result = newIdent
    of nnkVarTy:
      result = nnkVarTy.newTree(newIdent)
    of nnkRefTy:
      result = nnkRefTy.newTree(newIdent)
    of nnkPtrTy:
      result = nnkPtrTy.newTree(newIdent)
    else:
      result = newIdent

  for key, info in groups:
    if info.anySkipped:
      continue
    if info.typestate.typeParams.len > 0:
      continue # v0.6: generic typestates deferred
    if info.destStates.len != 1:
      continue # branching-return deferred

    for stateName, state in info.typestate.states:
      let stateBase = extractBaseName(stateName)
      if stateBase in info.coveredSources:
        continue
      # Build the tailored error message naming the proc, the wrong state,
      # the expected (one of) source state(s), and the location of the real
      # transition for navigability.
      let expectedList = info.coveredSources.join("' or '")
      let errorMsg =
        "Cannot call '" & info.name & "' on a value in state '" & stateBase &
        "'. Expected '" & expectedList & "'. (Defined at " &
        extractFilename(info.modulePath) & ")"

      let stateIdent = ident(stateBase)
      let procIdent = ident(info.name)
      # The decoy is exported (`*`) so it is visible at call sites in
      # downstream modules. Transitions are typically exported.
      let exportedName = nnkPostfix.newTree(ident("*"), procIdent)
      # Decoys carry only {.error.} — other pragmas like {.async.} aren't
      # propagated because {.error.} short-circuits before they would matter.
      let errorPragma =
        nnkPragma.newTree(nnkExprColonExpr.newTree(ident("error"), newLit(errorMsg)))
      # Build formal params: `auto` return (never reached — `{.error.}`
      # short-circuits) + first param with the wrong-state type + the same
      # trailing parameters as the real overload so `proc close(a, reason)`
      # generates `proc close(p: sink Frozen, reason: string)` decoys that
      # match the user's call shape.
      var formalParams = nnkFormalParams.newNimNode()
      formalParams.add ident("auto")
      formalParams.add nnkIdentDefs.newTree(
        ident("p"), replaceLeafState(info.firstParamType, stateIdent), newEmptyNode()
      )
      for extra in info.extraParams:
        formalParams.add extra.copyNimTree
      let decoyProc = nnkProcDef.newTree(
        exportedName,
        newEmptyNode(),
        newEmptyNode(),
        formalParams,
        errorPragma,
        newEmptyNode(),
        nnkStmtList.newTree(nnkDiscardStmt.newTree(newEmptyNode())),
      )
      result.add decoyProc

  # CFG analyzer pass (v0.9.0 §3.3). Runs AFTER F5 decoy emission so the
  # emitted decoys do not pollute the per-proc body walks below.
  runCfgAnalyzer()

  # Return empty - just for compile-time checking
  result.add newCommentStmtNode("typestates verified")
