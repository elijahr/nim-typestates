import std/[macros, tables]
import ../src/typestates/types

static:
  block test_state_creation:
    let s = State(name: "Open", typeName: newIdentNode("Open"))
    doAssert s.name == "Open"

  block test_transition_creation:
    let t = Transition(
      fromState: "Closed",
      toStates: @["Open", "Errored"],
      isWildcard: false
    )
    doAssert t.fromState == "Closed"
    doAssert t.toStates.len == 2
    doAssert "Open" in t.toStates

  block test_typestate_graph:
    var graph = TypestateGraph(name: "File")
    graph.states["Closed"] = State(name: "Closed")
    graph.states["Open"] = State(name: "Open")
    graph.transitions.add Transition(fromState: "Closed", toStates: @["Open"])

    doAssert graph.states.len == 2
    doAssert graph.transitions.len == 1

  block test_has_transition:
    var graph = TypestateGraph(name: "File")
    graph.states["Closed"] = State(name: "Closed")
    graph.states["Open"] = State(name: "Open")
    graph.transitions.add Transition(fromState: "Closed", toStates: @["Open"])

    doAssert graph.hasTransition("Closed", "Open")
    doAssert not graph.hasTransition("Open", "Closed")
    doAssert not graph.hasTransition("Closed", "Errored")

  block test_wildcard_transition:
    var graph = TypestateGraph(name: "File")
    graph.states["Closed"] = State(name: "Closed")
    graph.states["Open"] = State(name: "Open")
    graph.transitions.add Transition(fromState: "*", toStates: @["Closed"], isWildcard: true)

    doAssert graph.hasTransition("Open", "Closed")
    doAssert graph.hasTransition("Closed", "Closed")  # Even self via wildcard

  block test_valid_destinations:
    var graph = TypestateGraph(name: "File")
    graph.states["Closed"] = State(name: "Closed")
    graph.states["Open"] = State(name: "Open")
    graph.states["Errored"] = State(name: "Errored")
    graph.transitions.add Transition(fromState: "Closed", toStates: @["Open", "Errored"])
    graph.transitions.add Transition(fromState: "*", toStates: @["Closed"], isWildcard: true)

    let dests = graph.validDestinations("Closed")
    doAssert "Open" in dests
    doAssert "Errored" in dests
    doAssert "Closed" in dests  # via wildcard

  # Test default flags
  block defaultFlags:
    var graph = TypestateGraph(name: "Test")
    doAssert graph.strictTransitions == true, "strictTransitions should default to true"
    echo "default flags test passed"

  echo "types tests passed"
