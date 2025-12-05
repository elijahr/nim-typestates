import std/[macros, tables, options]
import ../src/typestates/types
import ../src/typestates/registry

# Test that bridges are preserved during typestate extension
static:
  # Clear registry (compile-time)
  typestateRegistry.clear()

  # Register first typestate with bridges
  var graph1 = TypestateGraph(
    name: "AuthFlow",
    isSealed: false,
    declaredAt: default(LineInfo),
    declaredInModule: "module1.nim"
  )
  graph1.states["Authenticated"] = State(
    name: "Authenticated",
    fullRepr: "Authenticated",
    typeName: newEmptyNode()
  )
  graph1.bridges.add Bridge(
    fromState: "Authenticated",
    toTypestate: "Session",
    toState: "Active",
    declaredAt: default(LineInfo)
  )
  registerTypestate(graph1)

  # Extend with additional state and bridge
  var graph2 = TypestateGraph(
    name: "AuthFlow",
    declaredAt: default(LineInfo),
    declaredInModule: "module2.nim"
  )
  graph2.states["Failed"] = State(
    name: "Failed",
    fullRepr: "Failed",
    typeName: newEmptyNode()
  )
  graph2.bridges.add Bridge(
    fromState: "Failed",
    toTypestate: "ErrorLog",
    toState: "Entry",
    declaredAt: default(LineInfo)
  )
  registerTypestate(graph2)

  # Verify both bridges are present
  let merged = typestateRegistry["AuthFlow"]
  doAssert merged.bridges.len == 2, "Should have 2 bridges after merge, got: " & $merged.bridges.len
  doAssert merged.states.len == 2, "Should have 2 states after merge"

  # Verify specific bridges
  var hasSessionBridge = false
  var hasErrorBridge = false
  for b in merged.bridges:
    if b.fromState == "Authenticated" and b.toTypestate == "Session":
      hasSessionBridge = true
    if b.fromState == "Failed" and b.toTypestate == "ErrorLog":
      hasErrorBridge = true

  doAssert hasSessionBridge, "Should have Session.Active bridge"
  doAssert hasErrorBridge, "Should have ErrorLog.Entry bridge"

echo "Bridge registry test passed"
