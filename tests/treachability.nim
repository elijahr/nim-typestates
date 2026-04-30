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
    let g = mkGraph(
      "F",
      ["A", "B", "C"],
      [("A", @["B"]), ("B", @["C"])],
      ["A"],
      ["C"],
    )
    let r = analyzeReachability(g)
    doAssert r.findings.len == 0,
      "linear chain expected no findings, got " & $r.findings.len

  block dead_state:
    let g = mkGraph(
      "F",
      ["A", "B", "Frozen"],
      [("A", @["B"])],
      ["A"],
      ["B"],
    )
    let r = analyzeReachability(g)
    doAssert r.findings.anyIt(it.kind == rfDead and it.stateName == "Frozen"),
      "expected dead Frozen, got " & $r.findings

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
    doAssert r.findings.anyIt(it.kind == rfDead and it.stateName == "C"),
      "C is unreachable from A so should be dead"

  block unreachable_is_dead_not_orphan:
    let g = mkGraph(
      "F",
      ["A", "B", "Z"],
      [("A", @["B"])],
      ["A"],
      [],
    )
    let r = analyzeReachability(g)
    doAssert r.findings.anyIt(it.kind == rfDead and it.stateName == "Z")
    doAssert (not r.findings.anyIt(it.kind == rfOrphan and it.stateName == "Z"))

  block no_entry_point:
    let g = mkGraph(
      "F",
      ["A", "B"],
      [("A", @["B"]), ("B", @["A"])],
      [],
      [],
    )
    let r = analyzeReachability(g)
    doAssert r.findings.anyIt(it.kind == rfNoEntryPoint)

  block implicit_initial_fallback:
    let g = mkGraph(
      "F",
      ["A", "B", "C"],
      [("A", @["B"]), ("B", @["C"])],
      [],
      [],
    )
    let r = analyzeReachability(g)
    doAssert r.implicitInitialFallback
    doAssert r.initialStatesUsed == @["A"]
    doAssert r.findings.len == 0

echo "treachability: all compile-time checks passed"
