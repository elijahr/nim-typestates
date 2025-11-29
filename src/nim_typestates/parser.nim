import std/[macros, tables, strutils]
import types

proc parseStates*(graph: var TypestateGraph, node: NimNode) =
  ## Parse: states State1, State2, State3 (command) or states(State1, State2, State3) (call)
  if node.kind notin {nnkCall, nnkCommand}:
    error("Expected call or command for states", node)

  # First child is "states", rest are state names
  for i in 1 ..< node.len:
    let stateNode = node[i]
    expectKind(stateNode, nnkIdent)
    let name = stateNode.strVal
    graph.states[name] = State(name: name, typeName: stateNode)

proc collectBranchTargets(node: NimNode): seq[string] =
  ## Collect all targets from: A | B | C
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
  ## Parse: FromState -> ToState or FromState -> A | B | C or * -> State
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

proc parseTransitionsBlock(graph: var TypestateGraph, node: NimNode) =
  ## Parse: transitions: (list of transitions)
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
  ## Parse the full typestate block body
  expectKind(name, nnkIdent)
  result = TypestateGraph(name: name.strVal, declaredAt: name.lineInfoObj)

  for child in body:
    case child.kind
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
