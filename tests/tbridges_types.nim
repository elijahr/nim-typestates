import ../src/typestates/types
import std/[tables, macros]

# Test bridge representation
block test_bridge_equality:
  let b1 = Bridge(
    fromState: "Authenticated",
    toTypestate: "Session",
    toState: "Active",
    declaredAt: default(LineInfo)
  )
  let b2 = Bridge(
    fromState: "Authenticated",
    toTypestate: "Session",
    toState: "Active",
    declaredAt: default(LineInfo)
  )
  doAssert b1 == b2, "Bridges with same source and dest should be equal"

block test_bridge_in_graph:
  var graph = TypestateGraph(
    name: "AuthFlow",
    declaredAt: default(LineInfo),
    declaredInModule: "test.nim"
  )
  let bridge = Bridge(
    fromState: "Authenticated",
    toTypestate: "Session",
    toState: "Active",
    declaredAt: default(LineInfo)
  )
  graph.bridges.add bridge
  doAssert graph.bridges.len == 1, "Bridge should be added to graph"
  doAssert graph.bridges[0].toTypestate == "Session", "Bridge destination typestate should be Session"

echo "Bridge types test passed"
