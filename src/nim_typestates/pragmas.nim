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

proc registerSealedStates*(modulePath: string, stateNames: seq[string]) {.compileTime.} =
  ## Register states from a sealed typestate for external checking.
  ##
  ## - `modulePath`: The module filename where the typestate is defined
  ## - `stateNames`: List of state type names to register
  if modulePath notin sealedTypestateModules:
    sealedTypestateModules[modulePath] = @[]
  for state in stateNames:
    if state notin sealedTypestateModules[modulePath]:
      sealedTypestateModules[modulePath].add state

proc isStateFromSealedTypestate*(stateName: string, currentModule: string): Option[string] {.compileTime.} =
  ## Check if a state is from a sealed typestate defined in another module.
  ##
  ## - `stateName`: The state type name to check
  ## - `currentModule`: The current module's filename
  ## - Returns: `some(modulePath)` if from external sealed typestate, `none` otherwise
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
  ##
  ## - `node`: AST node representing a type
  ## - Returns: The string name of the type
  case node.kind
  of nnkIdent:
    result = node.strVal
  of nnkSym:
    result = node.strVal
  of nnkBracketExpr:
    # Generic type like seq[T]
    result = node[0].strVal
  else:
    result = node.repr

proc extractAllTypeNames(node: NimNode): seq[string] =
  ## Extract all type names from a type AST node.
  ##
  ## Handles union types like `A | B | C` by returning all components.
  ##
  ## - `node`: AST node representing a type (possibly a union)
  ## - Returns: Sequence of all type names in the type
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
  ## Mark a proc as a state transition and validate it at compile time.
  ##
  ## This pragma macro validates that the transition is declared in
  ## the typestate. If the transition is not declared, compilation fails
  ## with a helpful error message.
  ##
  ## Validation rules:
  ##
  ## - First parameter type must be a registered state
  ## - Return type must be a valid transition target from that state
  ## - The transition must be declared in the typestate block
  ##
  ## - `procDef`: The proc definition to validate
  ## - Returns: The unmodified proc definition (if validation passes)
  ## - Raises: Compile-time error if transition is invalid
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
  let destTypeNames = extractAllTypeNames(returnType)

  # Look up typestate
  let graphOpt = findTypestateForState(sourceTypeName)
  if graphOpt.isNone:
    error(fmt"State '{sourceTypeName}' is not part of any registered typestate", procDef)

  let graph = graphOpt.get

  # Check if sealed and defined in different module
  let procModule = procDef.lineInfoObj.filename
  if graph.isSealed and procModule != graph.declaredInModule:
    error(fmt"""Cannot define transition on sealed typestate '{graph.name}'.
  The typestate is sealed (isSealed = true) and was defined in a different module.
  External modules can only define {{.notATransition.}} procs on sealed typestates.
  Hint: Use {{.notATransition.}} for read-only operations.""", procDef)

  # Validate each transition in the union
  for destTypeName in destTypeNames:
    if not graph.hasTransition(sourceTypeName, destTypeName):
      let validDests = graph.validDestinations(sourceTypeName)
      error(fmt"""Undeclared transition: {sourceTypeName} -> {destTypeName}
  Typestate '{graph.name}' does not declare this transition.
  Valid transitions from '{sourceTypeName}': {validDests}
  Hint: Add '{sourceTypeName} -> {destTypeName}' to the transitions block.""", procDef)

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
