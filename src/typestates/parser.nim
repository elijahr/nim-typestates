## Parser for the typestate DSL.
##
## This module transforms the AST from a `typestate` macro invocation into
## a `TypestateGraph` structure. It handles parsing of:
##
## - State declarations (`states Closed, Open, Errored`)
## - Transition declarations (`Closed -> Open | Errored`)
## - Wildcard transitions (`* -> Closed`)
##
## The parser operates at compile-time within macro context.
##
## **Internal module** - most users won't interact with this directly.

import std/[macros, tables, strutils]
import types

proc extractBaseName(node: NimNode): string =
  ## Extract the base type name from any type expression.
  ##
  ## - `Closed` -> "Closed"
  ## - `Container[T]` -> "Container"
  ## - `ref Closed` -> "Closed"
  ## - `ptr Container[T]` -> "Container"
  ## - `mymodule.State` -> "State"
  case node.kind
  of nnkIdent:
    result = node.strVal
  of nnkSym:
    result = node.strVal
  of nnkBracketExpr:
    # Generic: Container[T] -> extract "Container"
    result = extractBaseName(node[0])
  of nnkRefTy, nnkPtrTy:
    # ref/ptr: extract from inner type
    result = extractBaseName(node[0])
  of nnkDotExpr:
    # Qualified: mymodule.State -> extract "State"
    result = extractBaseName(node[1])
  of nnkPostfix:
    # Exported: State* -> extract "State"
    result = extractBaseName(node[1])
  else:
    result = node.repr.split("[")[0].split(".")[^1].strip(chars = {'*', ' '})

proc parseStates*(graph: var TypestateGraph, node: NimNode) =
  ## Parse a states declaration and add states to the graph.
  ##
  ## Accepts both command syntax (`states Closed, Open`) and
  ## call syntax (`states(Closed, Open)`).
  ##
  ## States can be any valid Nim type expression:
  ##
  ## - Simple identifiers: `Closed`, `Open`
  ## - Generic types: `Container[T]`, `Map[K, V]`
  ## - Ref types: `ref Closed`
  ## - Qualified names: `mymodule.State`
  ##
  ## - `graph`: The typestate graph to populate
  ## - `node`: AST node of the states declaration
  ## - Raises: Compile-time error if syntax is invalid
  ##
  ## Example AST inputs:
  ##
  ## ```
  ## # Simple: states Closed, Open
  ## Command
  ##   Ident "states"
  ##   Ident "Closed"
  ##   Ident "Open"
  ##
  ## # Generic: states Empty[T], Full[T]
  ## Command
  ##   Ident "states"
  ##   BracketExpr
  ##     Ident "Empty"
  ##     Ident "T"
  ##   BracketExpr
  ##     Ident "Full"
  ##     Ident "T"
  ## ```
  if node.kind notin {nnkCall, nnkCommand}:
    error("Expected call or command for states", node)

  # First child is "states", rest are state type expressions
  for i in 1 ..< node.len:
    let stateNode = node[i]
    let baseName = extractBaseName(stateNode)
    let fullRepr = stateNode.repr
    graph.states[fullRepr] = State(
      name: baseName,
      fullRepr: fullRepr,
      typeName: stateNode
    )

proc collectBranchTargets(node: NimNode): seq[string] =
  ## Recursively collect all target states from a branching expression.
  ##
  ## Handles the `|` operator for branching transitions like `Open | Errored`.
  ## States can be any valid type expression (simple, generic, ref, etc.).
  ##
  ## - `node`: AST node representing the target(s)
  ## - Returns: Sequence of state repr strings
  ##
  ## Examples:
  ##
  ## - `Open` -> `@["Open"]`
  ## - `Open | Errored` -> `@["Open", "Errored"]`
  ## - `Full[T] | Error[T]` -> `@["Full[T]", "Error[T]"]`
  ## - `A | B | C` -> `@["A", "B", "C"]`
  case node.kind
  of nnkIdent, nnkBracketExpr, nnkRefTy, nnkPtrTy, nnkDotExpr:
    # Any valid type expression - use its repr
    result = @[node.repr]
  of nnkInfix:
    if node[0].strVal == "|":
      result = collectBranchTargets(node[1]) & collectBranchTargets(node[2])
    else:
      error("Expected '|' in branching transition", node)
  else:
    # Fallback: try to use repr for any other node type
    result = @[node.repr]

proc parseTransition*(node: NimNode): Transition =
  ## Parse a single transition declaration.
  ##
  ## Supports three forms:
  ##
  ## - **Simple**: `Closed -> Open`
  ## - **Branching**: `Closed -> Open | Errored`
  ## - **Wildcard**: `* -> Closed`
  ##
  ## - `node`: AST node of the transition expression
  ## - Returns: A `Transition` object
  ## - Raises: Compile-time error if syntax is invalid
  ##
  ## Example AST for `Closed -> Open | Errored`:
  ##
  ## ```
  ## Infix
  ##   Ident "->"
  ##   Ident "Closed"
  ##   Infix
  ##     Ident "|"
  ##     Ident "Open"
  ##     Ident "Errored"
  ## ```
  ##
  ## Example AST for `* -> Closed` (wildcard parsed as nested prefix):
  ##
  ## ```
  ## Prefix
  ##   Ident "*"
  ##   Prefix
  ##     Ident "->"
  ##     Ident "Closed"
  ## ```

  # Handle wildcard syntax: * -> X parses as nested Prefix nodes
  if node.kind == nnkPrefix and node[0].strVal == "*":
    let innerNode = node[1]
    if innerNode.kind == nnkPrefix and innerNode[0].strVal == "->":
      let toStates = collectBranchTargets(innerNode[1])
      return Transition(
        fromState: "*",
        toStates: toStates,
        isWildcard: true,
        declaredAt: node.lineInfoObj
      )

  expectKind(node, nnkInfix)

  if node[0].strVal != "->":
    error("Expected '->' in transition", node[0])

  # Parse source state (can be any type expression)
  let sourceNode = node[1]
  var fromState: string
  var isWildcard = false

  case sourceNode.kind
  of nnkIdent:
    fromState = sourceNode.strVal
    if fromState == "*":
      isWildcard = true
  of nnkPrefix:
    # Handle * as prefix operator
    if sourceNode[0].strVal == "*":
      fromState = "*"
      isWildcard = true
    else:
      error("Unexpected prefix in transition source", sourceNode)
  of nnkBracketExpr, nnkRefTy, nnkPtrTy, nnkDotExpr:
    # Generic, ref, ptr, or qualified type - use repr
    fromState = sourceNode.repr
  else:
    # Fallback: try repr for any other valid type expression
    fromState = sourceNode.repr

  # Parse target state(s)
  let toStates = collectBranchTargets(node[2])

  result = Transition(
    fromState: fromState,
    toStates: toStates,
    isWildcard: isWildcard,
    declaredAt: node.lineInfoObj
  )

proc parseFlag(graph: var TypestateGraph, node: NimNode) =
  ## Parse a flag assignment like `strictTransitions = false`.
  ##
  ## - `graph`: The typestate graph to update
  ## - `node`: AST node of the assignment
  ## - Raises: Compile-time error for unknown flags
  expectKind(node, nnkAsgn)

  let flagName = node[0].strVal
  let flagValue = node[1]

  # Handle both nnkIdent (direct) and nnkSym (from quote do)
  if flagValue.kind notin {nnkIdent, nnkSym}:
    error("Expected true or false for flag value", flagValue)
  let value = flagValue.strVal == "true"

  case flagName
  of "strictTransitions":
    graph.strictTransitions = value
  of "isSealed":
    graph.isSealed = value
  else:
    error("Unknown flag: " & flagName & ". Valid flags: strictTransitions, isSealed", node)

proc parseTransitionsBlock(graph: var TypestateGraph, node: NimNode) =
  ## Parse the transitions block and add all transitions to the graph.
  ##
  ## - `graph`: The typestate graph to populate
  ## - `node`: AST node of the transitions block
  ## - Raises: Compile-time error if block is empty or malformed
  ##
  ## Example input:
  ##
  ## ```nim
  ## transitions:
  ##   Closed -> Open
  ##   Open -> Closed
  ## ```
  expectKind(node, nnkCall)

  # node[0] is "transitions", node[1] is the statement list
  if node.len < 2:
    error("transitions block is empty", node)

  let transBlock = node[1]
  expectKind(transBlock, nnkStmtList)

  for child in transBlock:
    let trans = parseTransition(child)
    graph.transitions.add(trans)

proc parseTypestateBody*(name: NimNode, body: NimNode): TypestateGraph =
  ## Parse a complete typestate block body into a TypestateGraph.
  ##
  ## This is the main entry point for parsing. It processes the full
  ## body of a `typestate` macro invocation.
  ##
  ## The typestate name can be a simple identifier or a generic type:
  ##
  ## - Simple: `typestate File:`
  ## - Generic: `typestate Container[T]:`
  ##
  ## - `name`: The typestate name (identifier or bracket expression)
  ## - `body`: The statement list containing states and transitions
  ## - Returns: A fully populated `TypestateGraph`
  ## - Raises: Compile-time error for invalid syntax
  ##
  ## Examples:
  ##
  ## ```nim
  ## typestate File:          # name = "File"
  ##   states Closed, Open
  ##   transitions:
  ##     Closed -> Open
  ##
  ## typestate Container[T]:  # name = "Container", with type param T
  ##   states Empty[T], Full[T]
  ##   transitions:
  ##     Empty[T] -> Full[T]
  ## ```
  let baseName = extractBaseName(name)
  result = TypestateGraph(
    name: baseName,
    declaredAt: name.lineInfoObj,
    declaredInModule: name.lineInfoObj.filename
  )

  for child in body:
    case child.kind
    of nnkAsgn:
      parseFlag(result, child)
    of nnkCall, nnkCommand:
      let sectionName = child[0].strVal
      case sectionName
      of "states":
        parseStates(result, child)
      of "transitions":
        parseTransitionsBlock(result, child)
      else:
        error("Unknown section in typestate block: " & sectionName, child)
    else:
      error("Unexpected node in typestate body: " & $child.kind, child)
