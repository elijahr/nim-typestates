## Unit tests for analyzeReachability over manually constructed graphs.
##
## Runs entirely at compile time because `TypestateGraph` carries `NimNode`
## fields which can only be constructed in macro/VM context.

import std/[tables, sequtils]
import ../src/typestates/[types, reachability]

proc mkGraph(
    name: string,
    states: openArray[string],
    transitions: openArray[(string, seq[string])],
    initial: openArray[string],
    terminal: openArray[string],
): TypestateGraph {.compileTime.} =
  result.name = name
  result.states = initTable[string, State]()
  for s in states:
    var st: State
    st.name = s
    st.fullRepr = s
    result.states[s] = st
  result.transitions = @[]
  for tup in transitions:
    let (src, dsts) = tup
    var t: Transition
    t.fromState = src
    t.toStates = dsts
    t.isWildcard = false
    result.transitions.add t
  result.initialStates = @initial
  result.terminalStates = @terminal

static:
  block linear_chain_no_findings:
    let g = mkGraph("F", ["A", "B", "C"], [("A", @["B"]), ("B", @["C"])], ["A"], ["C"])
    let r = analyzeReachability(g)
    doAssert r.findings.len == 0,
      "linear chain expected no findings, got " & $r.findings.len

  block dead_state:
    # Frozen has incoming from Iso, but Iso is itself unreachable from A
    # (Iso has no incoming and is not initial -> orphan). Frozen has
    # incoming -> dead.
    let g = mkGraph(
      "F",
      ["A", "B", "Iso", "Frozen"],
      [("A", @["B"]), ("Iso", @["Frozen"])],
      ["A"],
      ["B"],
    )
    let r = analyzeReachability(g)
    doAssert r.findings.anyIt(it.kind == rfDead and it.stateName == "Frozen"),
      "expected dead Frozen, got " & $r.findings
    doAssert r.findings.anyIt(it.kind == rfOrphan and it.stateName == "Iso"),
      "expected orphan Iso, got " & $r.findings

  block trap_states:
    let g = mkGraph(
      "F",
      ["A", "L1", "L2", "C"],
      [("A", @["L1"]), ("L1", @["L2"]), ("L2", @["L1"])],
      ["A"],
      ["C"],
    )
    let r = analyzeReachability(g)
    doAssert r.findings.anyIt(it.kind == rfTrap and it.stateName == "L1")
    doAssert r.findings.anyIt(it.kind == rfTrap and it.stateName == "L2")
    doAssert r.findings.anyIt(it.kind == rfTrap and it.stateName == "A")
    doAssert r.findings.anyIt(it.kind == rfOrphan and it.stateName == "C"),
      "C has no incoming and is not initial -> orphan; got " & $r.findings

  block unreachable_no_incoming_is_orphan:
    # State with no incoming edges and not declared `initial:` is reported
    # as orphan, NOT dead — the user's fix is different (declare initial vs
    # add upstream transition).
    let g = mkGraph("F", ["A", "B", "Z"], [("A", @["B"])], ["A"], [])
    let r = analyzeReachability(g)
    doAssert r.findings.anyIt(it.kind == rfOrphan and it.stateName == "Z"),
      "expected orphan Z, got " & $r.findings
    doAssert (not r.findings.anyIt(it.kind == rfDead and it.stateName == "Z"))

  block unreachable_with_incoming_is_dead:
    # State with an incoming edge from another unreachable state is dead.
    let g =
      mkGraph("F", ["A", "B", "X", "Y"], [("A", @["B"]), ("X", @["Y"])], ["A"], [])
    let r = analyzeReachability(g)
    # X has no incoming -> orphan. Y has incoming from X -> dead.
    doAssert r.findings.anyIt(it.kind == rfOrphan and it.stateName == "X"),
      "expected orphan X, got " & $r.findings
    doAssert r.findings.anyIt(it.kind == rfDead and it.stateName == "Y"),
      "expected dead Y, got " & $r.findings

  block no_entry_point:
    let g = mkGraph("F", ["A", "B"], [("A", @["B"]), ("B", @["A"])], [], [])
    let r = analyzeReachability(g)
    doAssert r.findings.anyIt(it.kind == rfNoEntryPoint)

  block single_state_initial_and_terminal:
    # One state, declared both initial and terminal, no transitions.
    # Should produce zero findings.
    let g = mkGraph("F", ["A"], [], ["A"], ["A"])
    let r = analyzeReachability(g)
    doAssert r.findings.len == 0,
      "single state initial+terminal expected no findings, got " & $r.findings

  block diamond_graph:
    # A -> B, A -> C, B -> D, C -> D. initial: A, terminal: D.
    # Every state lives; no findings.
    let g = mkGraph(
      "F",
      ["A", "B", "C", "D"],
      [("A", @["B"]), ("A", @["C"]), ("B", @["D"]), ("C", @["D"])],
      ["A"],
      ["D"],
    )
    let r = analyzeReachability(g)
    doAssert r.findings.len == 0, "diamond expected no findings, got " & $r.findings

  block bridge_source_not_trap:
    # Authenticated has no in-typestate transitions out, but bridges to
    # Session.Active. With terminal: Failed declared, Authenticated must
    # NOT be flagged trap.
    var g = mkGraph(
      "Auth",
      ["Pending", "Authenticated", "Failed"],
      [("Pending", @["Authenticated"]), ("Pending", @["Failed"])],
      ["Pending"],
      ["Failed"],
    )
    var b: Bridge
    b.fromState = "Authenticated"
    b.toModule = ""
    b.toTypestate = "Session"
    b.toState = "Active"
    g.bridges = @[b]
    let r = analyzeReachability(g)
    doAssert (
      not r.findings.anyIt(it.kind == rfTrap and it.stateName == "Authenticated")
    ), "Authenticated bridges out, must not be flagged trap; got " & $r.findings

  block bridge_source_via_input:
    # Same property, exercised through ReachabilityInput.bridgeSources
    # directly (the path the CLI takes).
    var inp: ReachabilityInput
    inp.typestateName = "Auth"
    inp.states = @["Pending", "Authenticated", "Failed"]
    inp.edges =
      @[
        GraphEdge(fromState: "Pending", toStates: @["Authenticated"], isWildcard: false),
        GraphEdge(fromState: "Pending", toStates: @["Failed"], isWildcard: false),
      ]
    inp.initialStates = @["Pending"]
    inp.terminalStates = @["Failed"]
    inp.bridgeSources = @["Authenticated"]
    let r = analyzeReachability(inp)
    doAssert (
      not r.findings.anyIt(it.kind == rfTrap and it.stateName == "Authenticated")
    ), "bridgeSources entry must exempt state from trap; got " & $r.findings

  block implicit_initial_fallback:
    let g = mkGraph("F", ["A", "B", "C"], [("A", @["B"]), ("B", @["C"])], [], [])
    let r = analyzeReachability(g)
    doAssert r.implicitInitialFallback
    doAssert r.initialStatesUsed == @["A"]
    doAssert r.findings.len == 0

echo "treachability: all compile-time checks passed"
