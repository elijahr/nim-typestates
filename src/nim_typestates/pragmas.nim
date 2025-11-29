import std/[macros, options, strformat]
import types, registry

proc extractTypeName(node: NimNode): string =
  ## Extract type name from a type node
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

macro transition*(procDef: untyped): untyped =
  ## Pragma macro to mark and validate state transitions.
  ##
  ## Example:
  ##   proc open(f: Closed): Open {.transition.} =
  ##     result = Open(f)
  result = procDef

  # Extract signature info
  let params = procDef.params
  if params.len < 2:
    error("Transition proc must take at least one state parameter", procDef)

  let firstParam = params[1]
  let sourceTypeName = extractTypeName(firstParam[1])
  let returnType = params[0]
  let destTypeName = extractTypeName(returnType)

  # Look up typestate
  let graphOpt = findTypestateForState(sourceTypeName)
  if graphOpt.isNone:
    error(fmt"State '{sourceTypeName}' is not part of any registered typestate", procDef)

  let graph = graphOpt.get

  # Validate transition
  if not graph.hasTransition(sourceTypeName, destTypeName):
    let validDests = graph.validDestinations(sourceTypeName)
    error(fmt"""Undeclared transition: {sourceTypeName} -> {destTypeName}
  Typestate '{graph.name}' does not declare this transition.
  Valid transitions from '{sourceTypeName}': {validDests}
  Hint: Add '{sourceTypeName} -> {destTypeName}' to the transitions block.""", procDef)

template notATransition*() {.pragma.}
  ## Mark a proc as intentionally not a state transition.
  ## Use this for procs that have side effects but don't change state.
  ## Required when {.strictTransitions.} is enabled on the typestate.
