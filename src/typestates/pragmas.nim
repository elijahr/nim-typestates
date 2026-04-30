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
        sourceState: (if firstParamTypes.len == 1: firstParamTypes[0] else: ""),
        destStates: destTypeNames,
        kind: pkTransition,
        declaredAt: procDef.lineInfoObj,
        modulePath: procDef.lineInfoObj.filename,
        firstParamType: allParams[1][^2].copyNimTree,
        extraParams: extraParams,
      )
    )

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
