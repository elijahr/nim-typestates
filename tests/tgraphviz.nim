import std/[macros, tables, strutils]
import ../src/nim_typestates/graphviz
import ../src/nim_typestates/types

macro testGraphviz(): untyped =
  var graph = TypestateGraph(name: "File")
  graph.states["Closed"] = State(name: "Closed")
  graph.states["Open"] = State(name: "Open")
  graph.states["Errored"] = State(name: "Errored")
  graph.transitions.add Transition(fromState: "Closed", toStates: @["Open", "Errored"])
  graph.transitions.add Transition(fromState: "Open", toStates: @["Closed"])
  graph.transitions.add Transition(fromState: "*", toStates: @["Closed"], isWildcard: true)

  let dot = generateDot(graph)

  doAssert "digraph File" in dot
  doAssert "Closed -> Open" in dot
  doAssert "Closed -> Errored" in dot
  doAssert "Open -> Closed" in dot
  # Wildcard should expand to all states
  doAssert "Errored -> Closed" in dot

  echo "Generated DOT:"
  echo dot

  result = newStmtList()

testGraphviz()
echo "graphviz test passed"
