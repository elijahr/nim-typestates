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
  let typeName = extractTypeNameAst(typeSlot)
  if typeName.len == 0:
    return
  let graphOpt = lookupTypestateForType(typeName, destructorTypes)
  if graphOpt.isNone:
    return
  let graph = graphOpt.get
  let stateType = extractBaseName(typeName)
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
    let isTerminal = block:
      var found = false
      for term in local.graph.terminalStates:
        if extractBaseName(term) == local.stateType:
          found = true
          break
      found
    if isTerminal:
      continue
    # Destructor recognition: the local's declared type's base name keys
    # the destructorTypes table. Match BOTH the type name (path (a) — state-
    # typed) and the attached object name (path (b)). For step 1 we only
    # have stateType (the *current* state); attached-object locals would
    # need an extra `declaredType` field — deferred until binding wires it.
    let hasDestructor = local.stateType in destructorTypes and
                        destructorTypes[local.stateType].name == local.graph.name
    if hasDestructor:
      continue
    let terminalList = local.graph.terminalStates.join(", ")
    error(
      "Typestate-bearing local '" & local.name &
        "' has not reached a terminal state at this " & edgeKind &
        ". Current state: '" & local.stateType & "' in typestate '" &
        local.graph.name & "'. Terminal states: [" & terminalList &
        "]. Either advance the local to a terminal state before " & edgeKind &
        ", or arrange for a `{.destructorTransition.}` to fire (held by an" &
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

  # Use the first reachable branch as the candidate post-state shape.
  # For each local in that branch, check agreement across all other branches.
  result = LiveState(locals: @[], reachable: true)
  let first = effective[0]
  for local in first.locals:
    var perBranchStates: seq[string] = @[local.stateType]
    var allReachThisLocal = true
    for other in effective[1 ..^ 1]:
      var matched = false
      for olocal in other.locals:
        if olocal.name == local.name:
          perBranchStates.add olocal.stateType
          matched = true
          break
      if not matched:
        # Local was rebound out of existence in one branch (e.g., consumed
        # by a transition). Treat as "this branch did not preserve the
        # local at the join" — for now drop it from the merge.
        allReachThisLocal = false
        break
    if not allReachThisLocal:
      continue

    # Agreement check.
    var allSame = true
    for s in perBranchStates[1 ..^ 1]:
      if s != perBranchStates[0]:
        allSame = false
        break

    if allSame:
      result.locals.add local
      continue

    # Different per-branch states: check the terminal-union exception.
    var allTerminal = true
    for s in perBranchStates:
      var isTerm = false
      for term in local.graph.terminalStates:
        if extractBaseName(term) == s:
          isTerm = true
          break
      if not isTerm:
        allTerminal = false
        break

    if allTerminal:
      # All branches reached a terminal (possibly different terminals). The
      # local has reached *a* terminal; downstream exit edges accept it.
      # Represent the merge by picking the first terminal as a witness — the
      # exact identity does not matter to validateExitEdge once any terminal
      # is reached, since hasDestructor / isTerminal both short-circuit.
      result.locals.add LocalTypestate(
        name: local.name,
        stateType: perBranchStates[0],
        graph: local.graph,
        declaredAt: local.declaredAt,
      )
      continue

    # CFG-002: irreconcilable divergence.
    error(
      "Typestate-bearing local '" & local.name &
        "' has inconsistent state across branches: [" &
        perBranchStates.join(", ") &
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

  else:
    # Default: recurse into children. Steps 5-8 will replace this with
    # call/discard/loop-specific handlers.
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
      validateExitEdge(
        endState, procInfo.body, "fall-through", destructorTypes
      )

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
