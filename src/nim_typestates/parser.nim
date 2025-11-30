## Parser for the typestate DSL.
##
## This module transforms the AST from a ``typestate`` macro invocation into
## a ``TypestateGraph`` structure. It handles parsing of:
##
## - State declarations (``states Closed, Open, Errored``)
## - Transition declarations (``Closed -> Open | Errored``)
## - Wildcard transitions (``* -> Closed``)
##
## The parser operates at compile-time within macro context.
##
## **Internal module** - most users won't interact with this directly.

import std/[macros, tables]
import types

proc parseStates*(graph: var TypestateGraph, node: NimNode) =
  ## Parse a states declaration and add states to the graph.
  ##
  ## Accepts both command syntax (``states Closed, Open``) and
  ## call syntax (``states(Closed, Open)``).
  ##
  ## :param graph: The typestate graph to populate
  ## :param node: AST node of the states declaration
  ## :raises: Compile-time error if syntax is invalid
  ##
  ## Example AST input::
  ##
  ##   Command
  ##     Ident "states"
  ##     Ident "Closed"
  ##     Ident "Open"
  if node.kind notin {nnkCall, nnkCommand}:
    error("Expected call or command for states", node)

  # First child is "states", rest are state names
  for i in 1 ..< node.len:
    let stateNode = node[i]
    expectKind(stateNode, nnkIdent)
    let name = stateNode.strVal
    graph.states[name] = State(name: name, typeName: stateNode)

proc collectBranchTargets(node: NimNode): seq[string] =
  ## Recursively collect all target states from a branching expression.
  ##
  ## Handles the ``|`` operator for branching transitions like ``Open | Errored``.
  ##
  ## :param node: AST node representing the target(s)
  ## :returns: Sequence of state names
  ##
  ## Examples:
  ##
  ## - ``Open`` -> ``@["Open"]``
  ## - ``Open | Errored`` -> ``@["Open", "Errored"]``
  ## - ``A | B | C`` -> ``@["A", "B", "C"]``
  case node.kind
  of nnkIdent:
    result = @[node.strVal]
  of nnkInfix:
    if node[0].strVal == "|":
      result = collectBranchTargets(node[1]) & collectBranchTargets(node[2])
    else:
      error("Expected '|' in branching transition", node)
  else:
    error("Unexpected node in transition target: " & $node.kind, node)

proc parseTransition*(node: NimNode): Transition =
  ## Parse a single transition declaration.
  ##
  ## Supports three forms:
  ##
  ## - **Simple**: ``Closed -> Open``
  ## - **Branching**: ``Closed -> Open | Errored``
  ## - **Wildcard**: ``* -> Closed``
  ##
  ## :param node: AST node of the transition expression
  ## :returns: A ``Transition`` object
  ## :raises: Compile-time error if syntax is invalid
  ##
  ## Example AST for ``Closed -> Open | Errored``::
  ##
  ##   Infix
  ##     Ident "->"
  ##     Ident "Closed"
  ##     Infix
  ##       Ident "|"
  ##       Ident "Open"
  ##       Ident "Errored"
  ##
  ## Example AST for ``* -> Closed`` (wildcard parsed as nested prefix)::
  ##
  ##   Prefix
  ##     Ident "*"
  ##     Prefix
  ##       Ident "->"
  ##       Ident "Closed"

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

  # Parse source state
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
  else:
    error("Expected state name or '*' in transition source", sourceNode)

  # Parse target state(s)
  let toStates = collectBranchTargets(node[2])

  result = Transition(
    fromState: fromState,
    toStates: toStates,
    isWildcard: isWildcard,
    declaredAt: node.lineInfoObj
  )

proc parseFlag(graph: var TypestateGraph, node: NimNode) =
  ## Parse a flag assignment like ``strictTransitions = false``.
  ##
  ## :param graph: The typestate graph to update
  ## :param node: AST node of the assignment
  ## :raises: Compile-time error for unknown flags
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
  ## :param graph: The typestate graph to populate
  ## :param node: AST node of the transitions block
  ## :raises: Compile-time error if block is empty or malformed
  ##
  ## Example input::
  ##
  ##   transitions:
  ##     Closed -> Open
  ##     Open -> Closed
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
  ## body of a ``typestate`` macro invocation.
  ##
  ## :param name: The typestate name identifier (e.g., ``File``)
  ## :param body: The statement list containing states and transitions
  ## :returns: A fully populated ``TypestateGraph``
  ## :raises: Compile-time error for invalid syntax
  ##
  ## Example::
  ##
  ##   typestate File:          # name = "File"
  ##     states Closed, Open    # parsed by parseStates
  ##     transitions:           # parsed by parseTransitionsBlock
  ##       Closed -> Open
  ##       Open -> Closed
  expectKind(name, nnkIdent)
  result = TypestateGraph(
    name: name.strVal,
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
