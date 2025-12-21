## Pragmas for marking and validating state transitions.
##
## This module provides the pragmas that users apply to their procs:
##
## - `{.transition.}` - Mark a proc as a state transition (validated)
## - `{.notATransition.}` - Mark a proc as intentionally not a transition
##
## The `{.transition.}` pragma performs compile-time validation to ensure
## that only declared transitions are implemented.

import std/[macros, options, strformat, tables]
import types, registry, verify

export verify

# Compile-time tracking of which modules have sealed typestates
var sealedTypestateModules* {.compileTime.}: Table[string, seq[string]]
  ## Maps module filename -> list of state type names from sealed typestates

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
    # Generic type like seq[T]
    result = node[0].strVal
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

proc extractAllTypeNames(node: NimNode): seq[string] =
  ## Extract all type names from a type AST node.
  ##
  ## Handles union types like `A | B | C` by returning all components.
  ##
  ## :param node: AST node representing a type (possibly a union)
  ## :returns: Sequence of all type names in the type
  case node.kind
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
    result = @[node[0].strVal]
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
  let sourceTypeName = extractTypeName(firstParam[1])
  let returnType = params[0]

  # Extract all destination types (handles union types like A | B)
  var destTypeNames = extractAllTypeNames(returnType)

  # Check if return type is a branch type (e.g., CreatedBranch)
  # If so, expand to the actual destination states
  if destTypeNames.len == 1:
    let branchInfo = findBranchTypeInfo(destTypeNames[0])
    if branchInfo.isSome:
      destTypeNames = branchInfo.get.destinations

  # Look up typestate
  let graphOpt = findTypestateForState(sourceTypeName)
  if graphOpt.isNone:
    error(
      fmt"State '{sourceTypeName}' is not part of any registered typestate", procDef
    )

  let graph = graphOpt.get

  # Transitions can only be defined in the same module as the typestate
  let procModule = procDef.lineInfoObj.filename
  if procModule != graph.declaredInModule:
    error(
      fmt"""Cannot define transition on typestate '{graph.name}' from external module.
  The typestate was defined in '{graph.declaredInModule}'.
  Transitions must be defined in the same module as the typestate declaration.
  Hint: Use {{.notATransition.}} for read-only operations on imported states.""",
      procDef,
    )

  # Check terminal constraint - cannot transition FROM terminal state
  if graph.isTerminalState(sourceTypeName):
    error(
      fmt"""Cannot transition FROM terminal state '{sourceTypeName}'.
  Terminal states are end states with no outgoing transitions.
  Consider removing '{sourceTypeName}' from the terminal: block if transitions from it are needed.""",
      procDef,
    )

  # Validate each transition in the union
  for destTypeName in destTypeNames:
    # Check initial constraint - cannot transition TO initial state
    if graph.isInitialState(destTypeName):
      error(
        fmt"""Cannot transition TO initial state '{destTypeName}'.
  Initial states can only be constructed, not transitioned to.
  Consider removing '{destTypeName}' from the initial: block if transitions to it are needed.""",
        procDef,
      )

    # Check if destination belongs to a different typestate (bridge case)
    let destGraphOpt = findTypestateForState(destTypeName)

    if destGraphOpt.isSome:
      let destGraph = destGraphOpt.get
      if destGraph.name != graph.name:
        # Cross-typestate transition: validate as a bridge
        if not graph.hasBridge(sourceTypeName, destGraph.name, destTypeName):
          let validBridges = graph.validBridges(sourceTypeName)
          let bridgeDest = destGraph.name & "." & destTypeName
          error(
            fmt"""Undeclared bridge: {sourceTypeName} -> {bridgeDest}
  Typestate '{graph.name}' does not declare this bridge.
  Valid bridges from '{sourceTypeName}': {validBridges}
  Hint: Add 'bridges: {sourceTypeName} -> {bridgeDest}' to {graph.name}.""",
            procDef,
          )
        # Bridge is valid, continue to next destination
        continue

    # Same typestate or destination not in any typestate: validate as regular transition
    if not graph.hasTransition(sourceTypeName, destTypeName):
      let validDests = graph.validDestinations(sourceTypeName)
      error(
        fmt"""Undeclared transition: {sourceTypeName} -> {destTypeName}
  Typestate '{graph.name}' does not declare this transition.
  Valid transitions from '{sourceTypeName}': {validDests}
  Hint: Add '{sourceTypeName} -> {destTypeName}' to the transitions block.""",
        procDef,
      )

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
