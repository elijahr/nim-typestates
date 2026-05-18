## Pragmas for marking and validating state transitions.
##
## This module provides the pragmas that users apply to their procs:
##
## - `{.transition.}` - Mark a proc as a state transition (validated)
## - `{.notATransition.}` - Mark a proc as intentionally not a transition
##
## The `{.transition.}` pragma performs compile-time validation to ensure
## that only declared transitions are implemented.

import std/[macros, options, sets, strformat, strutils, tables]
import types, registry, verify

export verify

# Compile-time tracking of which modules have sealed typestates
var sealedTypestateModules* {.compileTime.}: Table[string, seq[string]]
  ## Maps module filename -> list of state type names from sealed typestates

# Compile-time registry of transparent wrapper type names. Seeded with the
# common cases Result (nim-results), Option (std/options), and Future
# (chronos / std/asyncdispatch). The {.transition.} return-type inspector
# unwraps registered wrappers before matching the destination state, so a
# proc like `proc f(s: A): Result[B, E] {.transition.}` validates the
# A -> B edge transparently.
var transparentWrappers* {.compileTime.}: HashSet[string] =
  toHashSet(["Result", "Option", "Future"])

proc registerSealedStates*(
    modulePath: string, stateNames: seq[string]
) {.compileTime.} =
  ## Register states from a sealed typestate for external checking.
  ##
  ## :param modulePath: The module filename where the typestate is defined
  ## :param stateNames: List of state type names to register
  if modulePath notin sealedTypestateModules:
    sealedTypestateModules[modulePath] = @[]
  for state in stateNames:
    if state notin sealedTypestateModules[modulePath]:
      sealedTypestateModules[modulePath].add state

proc isStateFromSealedTypestate*(
    stateName: string, currentModule: string
): Option[string] {.compileTime.} =
  ## Check if a state is from a sealed typestate defined in another module.
  ##
  ## :param stateName: The state type name to check
  ## :param currentModule: The current module's filename
  ## :returns: `some(modulePath)` if from external sealed typestate, `none` otherwise
  for modulePath, states in sealedTypestateModules:
    if modulePath != currentModule and stateName in states:
      return some(modulePath)
  return none(string)

template transparentWrapper*() {.pragma.}
  ## Marker pragma (cosmetic, does NOT register). Apply to a generic type
  ## and follow with an explicit `static: registerTransparentWrapper("YourType")`
  ## call to register it as transparent for `{.transition.}` return-type
  ## validation.
  ##
  ## **Contract for wrapper authors:** the unwrap logic assumes the wrapped
  ## state type is the **first** generic argument of the wrapper. For
  ## `Wrapper[State, ...Extras]` this picks up `State`; for `Wrapper[A, B]`
  ## with no clear "primary" arg, only `A` is validated as a typestate
  ## destination. This matches the built-in seeds (`Result[T, E]`,
  ## `Option[T]`, `Future[T]`). If your wrapper puts the state anywhere
  ## other than position 0, do NOT register it — write a non-transparent
  ## wrapper and validate the transition at the call site instead.
  ##
  ## Example:
  ##
  ## ```nim
  ## type MyResult*[T] {.transparentWrapper.} = object
  ##   value: T
  ## static:
  ##   registerTransparentWrapper("MyResult")
  ## ```
  ##
  ## The pragma itself is a no-op in v1; actual registration is the
  ## separate `registerTransparentWrapper` call. The two-step form keeps
  ## type-level AST interactions simple and consistent with the
  ## `notATransition` marker pattern.

proc registerTransparentWrapper*(name: string) {.compileTime.} =
  ## Register a generic wrapper type as transparent for `{.transition.}`
  ## return-type validation. Name may be a base name (`"MyResult"`) or a
  ## module-qualified name (`"mymod.MyResult"`); the lookup checks both
  ## forms via `isTransparentWrapper`.
  transparentWrappers.incl(name)

proc unregisterTransparentWrapper*(name: string) {.compileTime.} =
  ## Remove a wrapper from the registry. Intended for users whose
  ## project-local type of the same name is itself a typestate STATE
  ## (rather than an error/option wrapper) and must be validated as the
  ## destination — not unwrapped. Call from a `static:` block near the
  ## typestate declaration, before the `{.transition.}` procs that use it.
  transparentWrappers.excl(name)

proc isTransparentWrapper*(name: string): bool {.compileTime.} =
  ## Predicate: is this type name registered as a transparent wrapper?
  ##
  ## Checks both the full name as given and the extracted base name, so
  ## module-qualified forms (`results.Result`) and bare forms (`Result`)
  ## both hit the registry.
  result =
    transparentWrappers.contains(name) or
    transparentWrappers.contains(extractBaseName(name))

proc extractTypeName(node: NimNode): string =
  ## Extract the type name from a type AST node.
  ##
  ## Handles various node types:
  ##
  ## - `nnkIdent`: Simple identifier like `Closed`
  ## - `nnkSym`: Symbol reference (after type resolution)
  ## - `nnkBracketExpr`: Generic type like `seq[T]` (extracts base)
  ## - `nnkCommand`: Modifier like `sink T` (extracts T)
  ## - `nnkVarTy`: `var T` type (extracts T)
  ## - `nnkRefTy`: `ref T` type (extracts T)
  ## - `nnkPtrTy`: `ptr T` type (extracts T)
  ##
  ## :param node: AST node representing a type
  ## :returns: The string name of the type
  case node.kind
  of nnkIdent:
    result = node.strVal
  of nnkSym:
    result = node.strVal
  of nnkBracketExpr:
    # Generic type like seq[T]. The head may be an Ident/Sym
    # ("State[T]") OR a module-qualified DotExpr ("mymod.State[T]").
    # Recursing delegates the head to the case that knows how to name
    # it — critically, DotExpr falls through to `node.repr` in the
    # `else` arm instead of crashing on `.strVal`.
    result = extractTypeName(node[0])
  of nnkCommand:
    # Modifier like `sink T` - extract the actual type
    if node.len >= 2 and node[0].kind == nnkIdent:
      let modifier = node[0].strVal
      if modifier == "sink":
        result = extractTypeName(node[1])
      else:
        result = node.repr
    else:
      result = node.repr
  of nnkVarTy:
    # var T - extract T
    result = extractTypeName(node[0])
  of nnkRefTy:
    # ref T - extract T
    result = extractTypeName(node[0])
  of nnkPtrTy:
    # ptr T - extract T
    result = extractTypeName(node[0])
  else:
    result = node.repr

proc extractAllSourceTypeNames(node: NimNode): seq[string] =
  ## Extract all source type names from a first-parameter type AST node.
  ##
  ## Mirrors `extractAllTypeNames` for return types: recurses into
  ## `nnkInfix |` union nodes to support sources like `Open | Filled`.
  ## Leaf nodes are delegated to `extractTypeName` so every shape that
  ## `extractTypeName` understands (plain idents, generics, `sink`, `var`,
  ## `ref`, `ptr`) works here too.
  ##
  ## Modifier and parenthesis unwrapping happens BEFORE the union check so
  ## that `sink (A | B)`, `var (A | B)`, and `(A | B)` split into their
  ## individual source states instead of collapsing to a single `"A | B"`
  ## string via the leaf fallback.
  ##
  ## :param node: AST node representing the first parameter's type
  ## :returns: Sequence of all source state type names, in source order
  var n = node
  # Strip parameter modifiers that wrap union sources.
  while true:
    case n.kind
    of nnkPar, nnkTupleConstr:
      # `(A | B)` parses as nnkPar (single element) or nnkTupleConstr
      # depending on Nim version; both wrap a single inner expression.
      if n.len == 1:
        n = n[0]
      else:
        break
    of nnkVarTy, nnkRefTy, nnkPtrTy:
      n = n[0]
    of nnkCommand:
      # `sink (A | B)` — first child is the modifier ident, second is the type.
      if n.len == 2 and n[0].kind == nnkIdent and n[0].strVal == "sink":
        n = n[1]
      else:
        break
    else:
      break
  if n.kind == nnkInfix and n[0].kind == nnkIdent and n[0].strVal == "|":
    result.add(extractAllSourceTypeNames(n[1]))
    result.add(extractAllSourceTypeNames(n[2]))
  else:
    # Pass the stripped node `n`, not the original `node`: without the
    # strip, a single parenthesized source like `(A)` would reach
    # `extractTypeName` as an nnkPar and fall through to `node.repr`,
    # producing the literal string `"(A)"` which never matches the
    # typestate graph.
    result.add(extractTypeName(n))

proc unwrapTransparent(node: NimNode): NimNode {.compileTime.} =
  ## Walk through transparent-wrapper `BracketExpr` layers and return the
  ## innermost non-wrapper type node.
  ##
  ## A wrapper is any `nnkBracketExpr` whose head name is registered via
  ## `registerTransparentWrapper` (seeded with `Result`, `Option`,
  ## `Future`). Non-bracket nodes and brackets whose head is NOT a
  ## registered wrapper are returned as-is, so union types, generic
  ## state types, and plain identifiers pass through unchanged.
  ##
  ## Safety: the head-name stack detects wrapper cycles (e.g.,
  ## `W1[W2[W1[X]]]`) and a depth cap of 32 acts as a backstop against
  ## pathological chains.
  ##
  ## :param node: return-type AST (or sub-node of a union)
  ## :returns: innermost non-wrapper node (or `node` unchanged)
  result = node
  var unwrappedHeads: seq[string] = @[]
  var depth = 0
  while result.kind == nnkBracketExpr and depth < 32:
    let headName = extractTypeName(result[0])
    if not isTransparentWrapper(headName):
      break
    if result.len < 2:
      # Defensive: a wrapper must have at least one generic arg for the
      # "first generic argument is the wrapped state" convention to be
      # meaningful. Empty-arg brackets can arise from macro rewrites or
      # malformed user input; treat as non-wrapper and stop unwrapping
      # rather than crashing the macro on an out-of-bounds access.
      break
    if headName in unwrappedHeads:
      error(
        "transparent wrapper cycle in return type: " & unwrappedHeads.join(" -> ") &
          " -> " & headName
      )
    unwrappedHeads.add(headName)
    result = result[1] # first generic arg = inner type
    inc depth
  if depth >= 32:
    error(
      "transparent wrapper depth cap (32) exceeded; chain so far: " &
        unwrappedHeads.join(" -> ")
    )

proc extractAllTypeNames(node: NimNode): seq[string] =
  ## Extract all type names from a type AST node.
  ##
  ## Handles union types like `A | B | C` by returning all components.
  ## Transparent wrappers on the outside (e.g., `Result[A | B, E]`) are
  ## unwrapped first via `unwrapTransparent` so the inner union / state
  ## is what gets matched against the typestate graph.
  ##
  ## Parenthesized unions and reference/pointer/sink modifiers inside a
  ## wrapper (e.g., `Result[(A | B), E]` or `Result[ref (A | B), E]`)
  ## are peeled before the union dispatch so each branch is matched
  ## individually, not as the literal `"(A | B)"` / `"ref (A | B)"`.
  ##
  ## Bracket heads are delegated to `extractTypeName` so a
  ## module-qualified generic like `mymod.State[T]` does not crash the
  ## macro on `node[0].strVal` (DotExpr has no strVal).
  ##
  ## :param node: AST node representing a type (possibly a union)
  ## :returns: Sequence of all type names in the type
  let unwrapped = unwrapTransparent(node)
  if unwrapped != node:
    return extractAllTypeNames(unwrapped)
  case node.kind
  of nnkPar, nnkTupleConstr:
    if node.len == 1:
      return extractAllTypeNames(node[0])
    result = @[node.repr]
  of nnkVarTy, nnkRefTy, nnkPtrTy:
    # `ref (A | B)`, `var A`, `ptr State[T]` — peel the modifier so the
    # inner shape participates in union / wrapper dispatch uniformly.
    return extractAllTypeNames(node[0])
  of nnkCommand:
    # `sink (A | B)` — first child is the modifier ident.
    if node.len == 2 and node[0].kind == nnkIdent and node[0].strVal == "sink":
      return extractAllTypeNames(node[1])
    result = @[node.repr]
  of nnkInfix:
    # Union type like `A | B`
    let op = node[0]
    if op.kind == nnkIdent and op.strVal == "|":
      result = extractAllTypeNames(node[1]) & extractAllTypeNames(node[2])
    else:
      result = @[node.repr]
  of nnkIdent:
    result = @[node.strVal]
  of nnkSym:
    result = @[node.strVal]
  of nnkBracketExpr:
    # Same delegation as `extractTypeName`: a DotExpr head
    # (`mymod.State[T]`) must not crash on `.strVal`.
    result = @[extractTypeName(node[0])]
  else:
    result = @[node.repr]

proc extractTypestatedParams*(procDef: NimNode): seq[TypestatedParam] {.compileTime.} =
  ## Walk a procDef's formal parameters and capture every typestate-bearing
  ## `var T` parameter's name + state type + owning graph name.
  ##
  ## Round-2 Finding #2: the CFG analyzer (verify.nim, `runCfgAnalyzer`)
  ## pre-populates `LiveState` with these entries at proc entry so a proc
  ## that takes `var f: Open` and returns early without consuming `f`
  ## correctly fires CFG-001.
  ##
  ## Parameter shape: nnkFormalParams is `[returnType, identDefs1, identDefs2, ...]`.
  ## Each `nnkIdentDefs` is `[name1, name2, ..., type, default]`. Grouped
  ## leading names (e.g. `proc f(a, b: var Open)`) share a single type slot
  ## at index `^2`.
  ##
  ## Scope decision — `var T` only:
  ## A `var T` parameter is borrowed; the caller's binding persists after
  ## the call and must observe a coherent post-state. The analyzer MUST
  ## verify the body brought it to terminal (or that a destructor will
  ## fire). That is the exact failure mode Finding #2 targets — the
  ## brief's canonical acceptance fixture is `proc f(var f: File[Open])`
  ## that returns early without consuming `f`.
  ##
  ## `sink T` and value-`T` parameters are NOT pre-populated:
  ## - `sink T`: ownership transfers into the callee; the proc itself
  ##   IS the transition (its signature encodes Src -> Dst). The result
  ##   becomes the destination state; the sink param's value dies with
  ##   the proc frame regardless of whether the body textually references
  ##   it (e.g., the canonical `result = Dst(src.Base)` body works, but
  ##   so does a body that constructs the result independently).
  ## - value `T`: a copy/move local to the proc; same scope as sink for
  ##   analysis purposes — no caller-visible post-state.
  ## Treating these as pre-populated would cause false positives in every
  ## existing `{.transition.}` proc body that doesn't textually reference
  ## the sink param (e.g., generic-typestate fixtures that construct the
  ## result from raw fields). The brief's `sink T should enter the set`
  ## guidance assumed the analyzer would recognize all body-side
  ## consumption shapes; in practice the body's exit edge IS the
  ## consumption point for sink/value params, which is best modeled by
  ## not pre-populating them at all.
  ##
  ## Resolution: each leading name's declared type is run through
  ## `extractTypeName` (peels generic brackets, etc.) and looked up
  ## against the typestate registry via `findTypestateForState`.
  ## Non-typestate-bearing params are skipped. Union-source param types
  ## (e.g. `var (A | B)`) are also skipped: the param's "current state"
  ## is ambiguous until the overload is resolved at the call site.
  result = @[]
  let params = procDef.params
  if params.kind != nnkFormalParams:
    return
  for i in 1 ..< params.len:
    let identDefs = params[i]
    if identDefs.kind != nnkIdentDefs:
      continue
    if identDefs.len < 3:
      continue
    let typeSlot = identDefs[^2]
    # Scope: `var T` only (see proc doc). `nnkVarTy` directly wraps the
    # underlying type; `sink T` is `nnkCommand(sink, T)`; bare `T` is
    # an ident/bracket/dot. Only `nnkVarTy` qualifies for pre-population.
    if typeSlot.kind != nnkVarTy:
      continue
    let paramTypes = extractAllSourceTypeNames(typeSlot)
    if paramTypes.len != 1:
      # Union-source (`A | B`) or unresolvable: defer to call-site
      # resolution; the analyzer cannot pre-bind without per-overload
      # source disambiguation.
      continue
    let typeName = paramTypes[0]
    let graphOpt = findTypestateForState(typeName)
    if graphOpt.isNone:
      continue
    let graph = graphOpt.get
    let stateBase = extractBaseName(typeName)
    for j in 0 ..< identDefs.len - 2:
      let nameNode = identDefs[j]
      var nameStr: string
      case nameNode.kind
      of nnkIdent, nnkSym:
        nameStr = nameNode.strVal
      of nnkPostfix:
        if nameNode.len >= 2 and nameNode[1].kind in {nnkIdent, nnkSym}:
          nameStr = nameNode[1].strVal
        else:
          continue
      of nnkPragmaExpr:
        if nameNode.len >= 1 and nameNode[0].kind in {nnkIdent, nnkSym}:
          nameStr = nameNode[0].strVal
        else:
          continue
      else:
        continue
      result.add TypestatedParam(
        name: nameStr, stateType: stateBase, graphName: graph.name
      )

proc hasSkipCfgAnalysisPragma(pragmaNode: NimNode): bool {.compileTime.} =
  ## AST scan for `{.skipCfgAnalysis.}` on a procDef's pragma node.
  ##
  ## Walks the `nnkPragma` children and matches `nnkIdent`/`nnkSym` with
  ## strVal `"skipCfgAnalysis"`. Combined forms like
  ## `{.raises: [], skipCfgAnalysis.}` or
  ## `{.destructorTransition, skipCfgAnalysis.}` are recognized because
  ## the scan iterates ALL children, not a single substring.
  ##
  ## Critically: this is NOT a CLI substring match (which the verifier
  ## documentation calls out as broken — see
  ## `project_typestates_verify_substring_matcher` memory).
  result = false
  if pragmaNode.kind == nnkEmpty:
    return
  for pragma in pragmaNode:
    case pragma.kind
    of nnkIdent, nnkSym:
      if pragma.strVal == "skipCfgAnalysis":
        return true
    of nnkExprColonExpr, nnkCall:
      if pragma.len >= 1 and pragma[0].kind in {nnkIdent, nnkSym} and
          pragma[0].strVal == "skipCfgAnalysis":
        return true
    else:
      discard

macro transition*(procDef: untyped): untyped =
  ## Mark a proc as a state transition and verify it at compile time.
  ##
  ## The compiler checks that the transition from the input state type
  ## to the return state type is declared in the corresponding typestate.
  ## If not, compilation fails with a diagnostic.
  ##
  ## This provides compile-time protocol enforcement: only declared
  ## transitions can be implemented.
  ##
  ## Example:
  ##
  ## ```nim
  ## proc open(f: Closed): Open {.transition.} =
  ##   result = Open(f)
  ##
  ## proc close(f: Open): Closed {.transition.} =
  ##   result = Closed(f)
  ## ```
  ##
  ## Error example:
  ##
  ## ```
  ## Error: Undeclared transition: Open -> Locked
  ##   Typestate 'File' does not declare this transition.
  ##   Valid transitions from 'Open': @["Closed"]
  ##   Hint: Add 'Open -> Locked' to the transitions block.
  ## ```
  result = procDef

  # Extract signature info
  let params = procDef.params
  if params.len < 2:
    error("Transition proc must take at least one state parameter", procDef)

  let firstParam = params[1]
  # nnkIdentDefs is [ident, ident, ..., type, default]. For grouped
  # parameters like `proc f(a, b: State)` there are multiple leading
  # idents, so `firstParam[1]` is the second IDENT, not the type.
  # The type is always second-to-last.
  let firstParamTypes = extractAllSourceTypeNames(firstParam[^2])
  let returnType = params[0]

  # Extract all destination types (handles union types like A | B)
  var destTypeNames = extractAllTypeNames(returnType)

  # Check if return type is a branch type (e.g., CreatedBranch)
  # If so, expand to the actual destination states
  if destTypeNames.len == 1:
    let branchInfo = findBranchTypeInfo(destTypeNames[0])
    if branchInfo.isSome:
      destTypeNames = branchInfo.get.destinations

  # Per-source validation with diagnostic accumulation. Every source in
  # the union gets the same validation chain as a single-source proc
  # (typestate lookup -> shared-graph check -> terminal source -> per-dest
  # initial/bridge/transition checks). Diagnostics are collected and
  # emitted as a single error() at the end so that a union with multiple
  # invalid sources reports every failure in one go.
  var allDiagnostics: seq[string] = @[]
  var commonGraph: TypestateGraph
  var commonGraphSet = false

  for sourceTypeName in firstParamTypes:
    let graphOpt = findTypestateForState(sourceTypeName)
    if graphOpt.isNone:
      allDiagnostics.add(
        fmt"State '{sourceTypeName}' is not part of any registered typestate"
      )
      continue

    let graph = graphOpt.get

    if not commonGraphSet:
      commonGraph = graph
      commonGraphSet = true
    elif graph.name != commonGraph.name:
      allDiagnostics.add(
        fmt"source `{sourceTypeName}` belongs to typestate `{graph.name}` but earlier sources belong to `{commonGraph.name}`; union sources must share a typestate"
      )
      continue

    # Transitions can only be defined in the same module as the typestate
    let procModule = procDef.lineInfoObj.filename
    if procModule != graph.declaredInModule:
      allDiagnostics.add(
        fmt"""Cannot define transition on typestate '{graph.name}' from external module.
  The typestate was defined in '{graph.declaredInModule}'.
  Transitions must be defined in the same module as the typestate declaration.
  Hint: Use {{.notATransition.}} for read-only operations on imported states."""
      )
      continue

    # Check terminal constraint - cannot transition FROM terminal state
    if graph.isTerminalState(sourceTypeName):
      allDiagnostics.add(
        fmt"""Cannot transition FROM terminal state '{sourceTypeName}'.
  Terminal states are end states with no outgoing transitions.
  Consider removing '{sourceTypeName}' from the terminal: block if transitions from it are needed."""
      )
      continue

    # Validate each destination for this source
    for destTypeName in destTypeNames:
      # Check initial constraint - cannot transition TO initial state
      if graph.isInitialState(destTypeName):
        allDiagnostics.add(
          fmt"""Cannot transition TO initial state '{destTypeName}'.
  Initial states can only be constructed, not transitioned to.
  Consider removing '{destTypeName}' from the initial: block if transitions to it are needed."""
        )
        continue

      # Check if destination belongs to a different typestate (bridge case)
      let destGraphOpt = findTypestateForState(destTypeName)

      if destGraphOpt.isSome:
        let destGraph = destGraphOpt.get
        if destGraph.name != graph.name:
          # Cross-typestate transition: validate as a bridge
          if not graph.hasBridge(sourceTypeName, destGraph.name, destTypeName):
            let validBridges = graph.validBridges(sourceTypeName)
            let bridgeDest = destGraph.name & "." & destTypeName
            allDiagnostics.add(
              fmt"""Undeclared bridge: {sourceTypeName} -> {bridgeDest}
  Typestate '{graph.name}' does not declare this bridge.
  Valid bridges from '{sourceTypeName}': {validBridges}
  Hint: Add 'bridges: {sourceTypeName} -> {bridgeDest}' to {graph.name}."""
            )
          # Bridge case handled (valid or reported); move to next destination
          continue

      # Same typestate or destination not in any typestate: regular transition
      if not graph.hasTransition(sourceTypeName, destTypeName):
        let validDests = graph.validDestinations(sourceTypeName)
        allDiagnostics.add(
          fmt"""Undeclared transition: {sourceTypeName} -> {destTypeName}
  Typestate '{graph.name}' does not declare this transition.
  state `{sourceTypeName}` is not a declared source of `{destTypeName}` in typestate `{graph.name}`
  Valid transitions from '{sourceTypeName}': {validDests}
  Hint: Add '{sourceTypeName} -> {destTypeName}' to the transitions block."""
        )

  if allDiagnostics.len > 0:
    error(allDiagnostics.join("\n"), procDef)

  # Check for {.raises.} pragma and enforce {.raises: [].}
  var hasRaises = false
  var raisesIsEmpty = true
  let pragmaNode = procDef.pragma

  if pragmaNode.kind != nnkEmpty:
    for pragma in pragmaNode:
      var pragmaName = ""
      case pragma.kind
      of nnkIdent, nnkSym:
        pragmaName = pragma.strVal
      of nnkExprColonExpr:
        if pragma[0].kind in {nnkIdent, nnkSym}:
          pragmaName = pragma[0].strVal
          if pragmaName == "raises":
            hasRaises = true
            # Check if the raises list is non-empty
            if pragma[1].kind == nnkBracket and pragma[1].len > 0:
              raisesIsEmpty = false
      of nnkCall:
        if pragma[0].kind in {nnkIdent, nnkSym}:
          pragmaName = pragma[0].strVal
          if pragmaName == "raises":
            hasRaises = true
            # raises() or raises([...])
            if pragma.len > 1:
              let arg = pragma[1]
              if arg.kind == nnkBracket and arg.len > 0:
                raisesIsEmpty = false
      else:
        discard

  if hasRaises and not raisesIsEmpty:
    let procName =
      if procDef[0].kind == nnkPostfix:
        procDef[0][1].strVal
      else:
        procDef[0].strVal
    error(
      fmt"""Transition '{procName}' has non-empty raises list.
  Transitions must have {{.raises: [].}} to ensure errors are modeled as states.

  Options:
  1. Return an error state (e.g., Open | OpenFailed)
  2. Handle exceptions internally and return error state on failure
  3. If truly impossible to raise, verify and keep {{.raises: [].}}

  See: https://elijahr.github.io/nim-typestates/guide/error-handling/""",
      procDef,
    )

  # If no raises pragma, add {.raises: [].} to enable compiler checking
  if not hasRaises:
    result.addPragma(nnkExprColonExpr.newTree(ident("raises"), nnkBracket.newTree()))

  # F5: register the transition for state-aware error decoy emission.
  #
  # The decoys themselves are emitted later by `verifyTypestates()` based on
  # the full registry of transitions in the module. Deferring lets us see
  # ALL overloads of a given proc name (e.g., `proc reset(p: PathA)`,
  # `proc reset(p: PathB)`) and only emit decoys for states NOT covered by
  # any real overload — avoiding "redefinition" conflicts.
  #
  # v0.5 scope (recorded here so `verifyTypestates` can apply uniform skip
  # rules even when a generic typestate, branching-return, or union-source
  # proc is registered): skip emission entirely when any of those apply.
  if allDiagnostics.len == 0 and commonGraphSet:
    var procNameStr: string
    if procDef[0].kind == nnkPostfix:
      procNameStr = procDef[0][1].strVal
    else:
      procNameStr = procDef[0].strVal

    # Encode the proc kind so verifyTypestates can distinguish transition
    # procs from notATransition procs. F5 only cares about transitions.
    var extraParams: seq[NimNode] = @[]
    let allParams = procDef.params
    for i in 2 ..< allParams.len:
      extraParams.add allParams[i].copyNimTree
    registerProc(
      RegisteredProc(
        name: procNameStr,
        sourceState: (if firstParamTypes.len == 1: firstParamTypes[0]
        else: ""),
        destStates: destTypeNames,
        kind: pkTransition,
        declaredAt: procDef.lineInfoObj,
        modulePath: procDef.lineInfoObj.filename,
        firstParamType: allParams[1][^2].copyNimTree,
        extraParams: extraParams,
        body: procDef.body,
        skipCfg: hasSkipCfgAnalysisPragma(procDef.pragma),
        typestatedParams: extractTypestatedParams(procDef),
      )
    )

template skipCfgAnalysis*() {.pragma.}
  ## Marker pragma: suppress the v0.9.0 CFG analyzer for this proc.
  ##
  ## When applied to a proc registered via `{.transition.}` or
  ## `{.destructorTransition.}`, the registered proc's `skipCfg` flag is
  ## set to `true`, telling the CFG analyzer (§3.3) to skip per-local
  ## terminal-reachability checks for the proc body. Useful as an escape
  ## hatch when the analyzer cannot model a proc's control flow (e.g.,
  ## opaque exit via FFI / setjmp-style continuations / asyncdispatch
  ## bodies the analyzer doesn't yet understand).
  ##
  ## The pragma itself is a no-op marker — its EFFECT is realized in the
  ## destructorTransition / transition macro's pragma-scan pass, which
  ## inspects `procDef.pragma` as AST nodes (NOT a stringified CLI
  ## substring scan, which would mis-handle combined pragmas like
  ## `{.raises: [], skipCfgAnalysis.}`).
  ##
  ## Example:
  ##
  ## ```nim
  ## proc tricky(x: A): B {.transition, skipCfgAnalysis.} =
  ##   ## CFG analyzer skips this proc.
  ##   B(x)
  ## ```

proc destructorTransitionCore(
    spec: NimNode, destrDef: NimNode
): NimNode {.compileTime.} =
  ## Shared core for both arities of `{.destructorTransition.}`.
  ##
  ## :param spec: `nil` for single-arg form; `nnkInfix(->,Src,Dst)` for two-arg form
  ## :param destrDef: The `=destroy` proc definition
  ##
  ## Implements:
  ##
  ## - DT-001: not a proc def
  ## - DT-002: proc name != `=destroy`
  ## - DT-003: wrong arity
  ## - DT-004: param not `var T`
  ## - DT-005: non-empty raises
  ## - DT-006: param type unknown to typestate registry + attachment registry
  ## - DT-007: typestate has no terminal states (single-arg only)
  ## - DT-008: source type is already terminal
  ## - DT-009: spec malformed (two-arg only)
  ## - DT-010: spec SrcState mismatch (two-arg only)
  ## - DT-011: spec DstState not terminal (two-arg only)
  ## - DT-013: deferred to 3.1.b.4 (requires populated attachment registry)
  ##
  ## See: design-destructortransition-cfg-analyzer-20260516.md §3.1, §3.1.1
  result = destrDef
  let hasSpec = spec != nil

  # Phase 0: Two-arg form — parse spec eagerly so spec-shape errors precede
  # proc-shape errors when both are present.
  var parsedSrcStateName, parsedDstStateName: string
  if hasSpec:
    if spec.kind != nnkInfix or spec[0].kind notin {nnkIdent, nnkSym} or
        spec[0].strVal != "->":
      error(
        "`destructorTransition` spec must be of the form " &
          "`SrcState -> DstState`; got `" & spec.repr & "`",
        spec,
      )
    parsedSrcStateName = extractTypeName(spec[1])
    parsedDstStateName = extractTypeName(spec[2])

  # Phase 1: Shape validation
  if destrDef.kind != nnkProcDef:
    error("`destructorTransition` may only be applied to a proc definition", destrDef)

  let procNameNode =
    if destrDef[0].kind == nnkPostfix:
      destrDef[0][1]
    else:
      destrDef[0]
  # For `=destroy`, AccQuoted has two children: `=` and `destroy`.
  # Concatenate all child idents to recover the full operator-ident name.
  let procName =
    case procNameNode.kind
    of nnkAccQuoted:
      var parts = ""
      for c in procNameNode:
        if c.kind in {nnkIdent, nnkSym}:
          parts.add c.strVal
      parts
    of nnkIdent, nnkSym:
      procNameNode.strVal
    else:
      procNameNode.repr
  if procName != "=destroy":
    error(
      "`destructorTransition` may only be applied to a `=destroy` hook " & "(got `" &
        procName & "`); use `{.transition.}` for non-destructor procs",
      destrDef,
    )

  if destrDef.params.len != 2:
    # params[0] is return type, params[1..N] are formal params.
    # destructors take exactly one var-self param.
    error(
      "`=destroy` hook with `{.destructorTransition.}` must take exactly one " &
        "parameter (the var self); got " & $(destrDef.params.len - 1),
      destrDef,
    )

  let paramTypeNode = destrDef.params[1][^2]
  if paramTypeNode.kind != nnkVarTy:
    error(
      "`=destroy` hook with `{.destructorTransition.}` must take its parameter " &
        "by `var`; got `" & paramTypeNode.repr & "`",
      destrDef,
    )

  let paramTypeName = extractTypeName(paramTypeNode[0])

  # Phase 2: Resolve the typestate graph and source state. Two paths:
  #   (a) state-typed param: param type IS a registered typestate state
  #   (b) attached-object param: param type is bound via §3.7 attachment
  #
  # NOTE: The §3.7 attachment registry is populated by sub-phase 3.1.b.4.
  # Until then `findAttachmentForType` always returns `none`, so path (b)
  # always fails and DT-006 fires for attached-object-param destructors.
  # This is intentional: the failure mode is honest (the attachment
  # pragma doesn't exist yet) and the path itself is correctly wired.
  var graph: TypestateGraph
  var sourceStateName: string
  var attachedObjectTypeNameOpt = none(string)

  let graphOpt = findTypestateForState(paramTypeName)
  if graphOpt.isSome:
    graph = graphOpt.get
    sourceStateName = paramTypeName
  else:
    let attOpt = findAttachmentForType(paramTypeName)
    if attOpt.isNone:
      # DT-006: both lookups failed.
      error(
        "`destructorTransition` parameter type `" & paramTypeName &
          "` is not part of any registered typestate AND no " &
          "typestate-attachment pragma (§3.7) was found for it.",
        paramTypeNode,
      )
    let att = attOpt.get
    if att.typestateName notin typestateRegistry:
      error(
        "internal: attachment registry references unknown typestate `" &
          att.typestateName & "`",
        paramTypeNode,
      )
    graph = typestateRegistry[att.typestateName]
    sourceStateName = att.initialState
    attachedObjectTypeNameOpt = some(paramTypeName)

  # Phase 3: Terminal-state sanity (DT-007, DT-008)
  if graph.terminalStates.len == 0:
    error(
      "`destructorTransition` requires the typestate `" & graph.name &
        "` to declare at least one terminal state via `terminal:`; " &
        "destructors model terminal transitions and need an explicit terminal.",
      destrDef,
    )
  if graph.isTerminalState(sourceStateName):
    error(
      "`destructorTransition` source type `" & sourceStateName &
        "` is already a terminal state of typestate `" & graph.name &
        "`; destructor cannot perform a transition",
      destrDef,
    )

  # Phase 4: Two-arg form cross-check (DT-010, DT-011, DT-013)
  if hasSpec:
    let srcMatches = parsedSrcStateName == sourceStateName
    if not srcMatches:
      if attachedObjectTypeNameOpt.isSome:
        # DT-013: attached-object-param SrcState mismatch.
        error(
          "two-arg `destructorTransition` SrcState (`" & parsedSrcStateName &
            "`) does not match the attached object's initial state (`" & sourceStateName &
            "`); attached object type `" & paramTypeName & "` is bound to typestate `" &
            graph.name & "` with initial state `" & sourceStateName & "`.",
          spec,
        )
      else:
        # DT-010: state-typed-param mismatch.
        error(
          "`destructorTransition` spec SrcState `" & parsedSrcStateName &
            "` does not match destructor parameter type `" & paramTypeName & "`",
          spec,
        )
    if parsedDstStateName notin graph.terminalStates:
      let terminals = graph.terminalStates.join(", ")
      error(
        "`destructorTransition` spec DstState `" & parsedDstStateName &
          "` is not a terminal state of typestate `" & graph.name &
          "`; declared terminals: " & terminals,
        spec,
      )

  # Phase 5: raises validation + auto-injection (mirrors transition* logic)
  var hasRaises = false
  var raisesIsEmpty = true
  let pragmaNode = destrDef.pragma
  if pragmaNode.kind != nnkEmpty:
    for pragma in pragmaNode:
      case pragma.kind
      of nnkIdent, nnkSym:
        discard
      of nnkExprColonExpr:
        if pragma[0].kind in {nnkIdent, nnkSym} and pragma[0].strVal == "raises":
          hasRaises = true
          if pragma[1].kind == nnkBracket and pragma[1].len > 0:
            raisesIsEmpty = false
      of nnkCall:
        if pragma[0].kind in {nnkIdent, nnkSym} and pragma[0].strVal == "raises":
          hasRaises = true
          if pragma.len > 1:
            let arg = pragma[1]
            if arg.kind == nnkBracket and arg.len > 0:
              raisesIsEmpty = false
      else:
        discard
  if hasRaises and not raisesIsEmpty:
    error(
      "`destructorTransition` destructor `" & procName &
        "` has non-empty raises list; destructors must have `{.raises: [].}`",
      destrDef,
    )
  if not hasRaises:
    result.addPragma(nnkExprColonExpr.newTree(ident("raises"), nnkBracket.newTree()))

  # Phase 6: Register the destructor in the proc registry.
  let destStates =
    if hasSpec:
      @[parsedDstStateName]
    else:
      graph.terminalStates
  let skipCfg = hasSkipCfgAnalysisPragma(destrDef.pragma)
  registerProc(
    RegisteredProc(
      name: "=destroy",
      sourceState: sourceStateName,
      destStates: destStates,
      kind: pkDestructorTransition,
      declaredAt: destrDef.lineInfoObj,
      modulePath: destrDef.lineInfoObj.filename,
      firstParamType: paramTypeNode.copyNimTree,
      extraParams: @[],
      body: destrDef.body,
      skipCfg: skipCfg,
      attachedObjectTypeName: attachedObjectTypeNameOpt,
      typestatedParams: extractTypestatedParams(destrDef),
    )
  )

macro destructorTransition*(destrDef: untyped): untyped =
  ## Mark a `=destroy` hook as a terminal state transition (single-arg form).
  ##
  ## Use when the typestate declares exactly one terminal state OR when the
  ## destructor consumes the union of all terminals; the destination is
  ## inferred as the typestate's `terminalStates` set.
  ##
  ## Example:
  ##
  ## ```nim
  ## typestate Connection:
  ##   states Open, Closed
  ##   terminal: Closed
  ##   transitions:
  ##     Open -> Closed
  ##
  ## proc `=destroy`(c: var Open) {.destructorTransition.} =
  ##   discard
  ## ```
  ##
  ## See: §3.1 of design-destructortransition-cfg-analyzer-20260516.md
  destructorTransitionCore(nil, destrDef)

macro destructorTransition*(spec: untyped, destrDef: untyped): untyped =
  ## Mark a `=destroy` hook as a terminal state transition (two-arg form).
  ##
  ## Use when the typestate declares multiple terminal states and the
  ## destructor pins exactly one. The spec syntax `SrcState -> DstState`
  ## mirrors `{.transition: A -> B.}` for visual symmetry.
  ##
  ## Example:
  ##
  ## ```nim
  ## proc `=destroy`(c: var Open)
  ##     {.destructorTransition: Open -> Closed.} =
  ##   discard
  ## ```
  ##
  ## See: §3.1 of design-destructortransition-cfg-analyzer-20260516.md
  destructorTransitionCore(spec, destrDef)

proc extractTypeDeclName(typeDef: NimNode): string {.compileTime.} =
  ## Extract the base type name from a `nnkTypeDef` node, stripping
  ## visibility postfix (`*`) and generic params (`[T]`).
  ##
  ## Examples (input node[0] shape -> result):
  ## - `PinnedScope`           (nnkIdent)                  -> `"PinnedScope"`
  ## - `PinnedScope*`          (nnkPostfix)                -> `"PinnedScope"`
  ## - `PinnedScope[MT, CC]`   (nnkBracketExpr)            -> `"PinnedScope"`
  ## - `PinnedScope*[MT, CC]`  (nnkPragmaExpr->Postfix)    -> `"PinnedScope"`
  ##
  ## NOTE: when a pragma is on a type decl, `typeDef[0]` may be wrapped in
  ## an `nnkPragmaExpr` whose `[0]` is the name node and `[1]` is the
  ## pragma. We accept `typeDef` here so the caller can pass the raw
  ## TypeDef without prior unwrapping.
  var nameNode = typeDef[0]
  if nameNode.kind == nnkPragmaExpr:
    nameNode = nameNode[0]
  if nameNode.kind == nnkPostfix:
    # `name*` form -> strip the `*`
    nameNode = nameNode[1]
  case nameNode.kind
  of nnkIdent, nnkSym:
    return nameNode.strVal
  of nnkBracketExpr:
    # `name[T]` — generic. Head should be Ident/Sym.
    let head = nameNode[0]
    if head.kind in {nnkIdent, nnkSym}:
      return head.strVal
    else:
      return head.repr
  else:
    return nameNode.repr

proc attachTypestateCore*(
    typestateName: string, initial: NimNode, typeDef: NimNode
): NimNode {.compileTime.} =
  ## Shared core for the per-typestate attachment-pragma macros emitted
  ## by the `typestate` macro (see `codegen.generateAttachmentMarker`).
  ##
  ## Implements §3.7 verification rules TA-001..TA-004 and registers the
  ## binding in `typestateAttachments` so destructorTransition's path (b)
  ## source resolution and CFG analyzer scope detection can recover the
  ## initial state from the attached object type name.
  ##
  ## TA-001 is unreachable through this entry point — the per-typestate
  ## macro emitter only runs WHEN the typestate is declared, so an
  ## undeclared `<TypestateName>` surfaces as Nim's "undeclared identifier"
  ## error at parse time, attributed to the pragma site. We still emit
  ## the TA-001 message defensively in case the registry is concurrently
  ## mutated.
  ##
  ## :param typestateName: Name of the typestate whose marker pragma fired
  ## :param initial: The initial-state argument as written in the pragma
  ## :param typeDef: The TypeDef AST the pragma decorates
  ## :returns: `typeDef` unchanged (the pragma is registration-only)
  if typestateName notin typestateRegistry:
    # TA-001 (defensive — see proc doc).
    error(
      "typestate-attachment pragma: `" & typestateName &
        "` is not a declared typestate; declare it with `typestate " & typestateName &
        ": ...` before attaching",
      initial,
    )
  let graph = typestateRegistry[typestateName]
  let initialStateName = extractTypeName(initial)

  # TA-002: initial state must exist in the typestate's state list.
  var stateExists = false
  var declaredStates: seq[string] = @[]
  for stateKey, state in graph.states:
    declaredStates.add state.name
    if state.name == initialStateName:
      stateExists = true
  if not stateExists:
    error(
      "typestate-attachment pragma: `" & initialStateName &
        "` is not a state of typestate `" & typestateName & "`; declared states: " &
        $declaredStates,
      initial,
    )

  # TA-003: initial state must not be terminal.
  if graph.isTerminalState(initialStateName):
    error(
      "typestate-attachment pragma: initial state `" & initialStateName &
        "` is a terminal state of typestate `" & typestateName & "`; instances of `" &
        extractTypeDeclName(typeDef) &
        "` would start in a terminal state with no valid transitions",
      initial,
    )

  let typeName = extractTypeDeclName(typeDef)
  let typeKey = extractBaseName(typeName)

  # TA-004: duplicate attachment.
  let prior = findAttachmentForType(typeKey)
  if prior.isSome:
    let p = prior.get
    error(
      "typestate-attachment pragma: type `" & typeName &
        "` is already attached to typestate `" & p.typestateName &
        "`; a type may attach to at most one typestate",
      initial,
    )

  # Register the attachment. We use the LineInfo of the `initial` node
  # because that pins the diagnostic to the pragma site, not the type
  # body — useful for downstream tooling.
  addAttachment(
    typeKey,
    AttachmentInfo(
      typestateName: typestateName,
      initialState: initialStateName,
      declaredAt: initial.lineInfoObj,
    ),
  )

  # Pragma is registration-only — return the type decl unchanged.
  result = typeDef

template notATransition*() {.pragma.}
  ## Mark a proc as intentionally not a state transition.
  ##
  ## Use this pragma for procs that operate on state types but don't
  ## change the state. This is required when `strictTransitions` is
  ## enabled on the typestate.
  ##
  ## When to use:
  ##
  ## - Procs that read from a state type
  ## - Procs that perform I/O without changing state
  ## - Procs that modify the underlying data without state transition
  ##
  ## Example:
  ##
  ## ```nim
  ## # Side effects without state change
  ## proc write(f: Open, data: string) {.notATransition.} =
  ##   rawWrite(f.handle, data)
  ##
  ## # Pure functions don't need this (use `func` instead)
  ## func path(f: Open): string = f.File.path
  ## ```
