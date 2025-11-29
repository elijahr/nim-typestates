import std/[macros, tables]
import ../src/nim_typestates/registry
import ../src/nim_typestates/types

macro testRegistry(): untyped =
  var graph = TypestateGraph(name: "File")
  graph.states["Closed"] = State(name: "Closed")
  graph.states["Open"] = State(name: "Open")
  graph.transitions.add Transition(fromState: "Closed", toStates: @["Open"])

  registerTypestate(graph)

  doAssert hasTypestate("File"), "File typestate not found in registry"
  doAssert not hasTypestate("Socket"), "Socket should not exist"

  let retrieved = getTypestate("File")
  doAssert retrieved.name == "File"
  doAssert retrieved.states.len == 2

  result = newStmtList()

testRegistry()
echo "registry test passed"
