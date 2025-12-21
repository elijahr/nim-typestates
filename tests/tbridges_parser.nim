import std/[macros, tables]
import ../src/typestates/parser
import ../src/typestates/types

macro testParseBridges(): untyped =
  # Test input AST that mimics:
  # bridges:
  #   Authenticated -> Session.Active
  #   Failed -> ErrorLog.Entry
  let bridgesBlock = quote:
    bridges:
      Authenticated -> Session.Active
      Failed -> ErrorLog.Entry

  var graph = TypestateGraph(
    name: "AuthFlow", declaredAt: default(LineInfo), declaredInModule: "test.nim"
  )

  # quote do creates a Call node directly for bridges: ...
  parseBridgesBlock(graph, bridgesBlock)

  # Verify bridges were parsed
  doAssert graph.bridges.len == 2, "Should parse 2 bridges, got: " & $graph.bridges.len
  doAssert graph.bridges[0].fromState == "Authenticated"
  doAssert graph.bridges[0].toTypestate == "Session"
  doAssert graph.bridges[0].toState == "Active"
  doAssert graph.bridges[1].fromState == "Failed"
  doAssert graph.bridges[1].toTypestate == "ErrorLog"
  doAssert graph.bridges[1].toState == "Entry"

  result = newStmtList()

testParseBridges()
echo "Bridge parser test passed"
