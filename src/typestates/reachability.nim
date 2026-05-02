## Reachability and liveness analysis for typestate graphs.
##
## Computes:
## - **Dead states**: unreachable from any initial state.
## - **Trap states**: reachable, but cannot reach any terminal state
##   (only when `terminal:` is declared).
## - **Orphan states**: unreachable, with no incoming transitions, and not
##   declared `initial:`. Reported instead of `rfDead` for these states
##   because the user-facing fix is different (declare initial, or wire an
##   incoming transition) versus dead-via-other-dead.
## - **No-entry-point**: no `initial:` declared and every state has at
##   least one incoming transition (graph is one or more cycles).
##
## Used by both the macro-side parser (compile-time `warning(...)`
## emission) and the CLI verifier (populates `VerifyResult.warnings`).

import std/[tables, sets, sequtils, strutils, deques]
import types
import findings

type
  ReachabilityFindingKind* = enum
    rfDead
    rfTrap
    rfOrphan
    rfNoEntryPoint

  ReachabilityFinding* = object
    kind*: ReachabilityFindingKind
    stateName*: string ## "" for rfNoEntryPoint
    typestateName*: string

  ReachabilityReport* = object
    findings*: seq[ReachabilityFinding]
    initialStatesUsed*: seq[string] ## explicit or implicit
    terminalStatesUsed*: seq[string]
    implicitInitialFallback*: bool ## true when initialStates was empty

  GraphEdge* = object ## A directed edge in a typestate graph, normalized to base names.
    fromState*: string
    toStates*: seq[string]
    isWildcard*: bool

  ReachabilityInput* = object
    ## Runtime-buildable view of a typestate graph for the analyzer.
    ##
    ## Avoids depending on `TypestateGraph` (which carries `NimNode` fields
    ## that are only constructible at compile time). Both the macro-side and
    ## CLI-side callers project their respective graph representations into
    ## this shape.
    typestateName*: string
    states*: seq[string] ## base state names
    edges*: seq[GraphEdge]
    initialStates*: seq[string] ## raw user-written, normalized internally
    terminalStates*: seq[string]
    bridgeSources*: seq[string]
      ## Base names of states that are sources of a `bridges:` edge to
      ## another typestate. Treated as liveness exits: a state that bridges
      ## out is not a trap even if it has no in-typestate path to a terminal.

proc fromGraph*(graph: TypestateGraph): ReachabilityInput =
  ## Project a compile-time `TypestateGraph` into a `ReachabilityInput`.
  ##
  ## Normalizes states and edge endpoints to base names so the analyzer can
  ## treat generic and non-generic typestates uniformly.
  result.typestateName = graph.name
  result.states = @[]
  for s in graph.states.keys:
    result.states.add extractBaseName(s)
  result.edges = @[]
  for t in graph.transitions:
    var e: GraphEdge
    e.fromState = extractBaseName(t.fromState)
    e.toStates = t.toStates.mapIt(extractBaseName(it))
    e.isWildcard = t.isWildcard
    result.edges.add e
  result.initialStates = graph.initialStates.mapIt(extractBaseName(it))
  result.terminalStates = graph.terminalStates.mapIt(extractBaseName(it))
  result.bridgeSources = @[]
  for b in graph.bridges:
    result.bridgeSources.add extractBaseName(b.fromState)

proc buildAdjacency(
    inp: ReachabilityInput
): tuple[forward, reverse: Table[string, seq[string]]] =
  ## Build adjacency tables keyed by base state names.
  ##
  ## - Wildcard sources expand to every state except those declared terminal.
  ## - Branching destinations expand to one edge per destination.
  result.forward = initTable[string, seq[string]]()
  result.reverse = initTable[string, seq[string]]()
  for s in inp.states:
    result.forward[s] = @[]
    result.reverse[s] = @[]

  let terminalBases = inp.terminalStates.mapIt(extractBaseName(it))

  for t in inp.edges:
    let sources =
      if t.isWildcard:
        inp.states.filterIt(it notin terminalBases)
      else:
        @[t.fromState]
    for src in sources:
      for dst in t.toStates:
        if src in result.forward:
          result.forward[src].add dst
        if dst in result.reverse:
          result.reverse[dst].add src

proc bfs(adj: Table[string, seq[string]], starts: seq[string]): HashSet[string] =
  ## Standard BFS reachability over a directed adjacency table.
  result = initHashSet[string]()
  var queue = initDeque[string]()
  for s in starts:
    if s notin result:
      result.incl s
      queue.addLast s
  while queue.len > 0:
    let n = queue.popFirst()
    if n in adj:
      for nbr in adj[n]:
        if nbr notin result:
          result.incl nbr
          queue.addLast nbr

proc analyzeReachability*(inp: ReachabilityInput): ReachabilityReport =
  ## Run reachability/liveness analysis on a `ReachabilityInput`.
  ##
  ## See module documentation for the categories of finding produced.
  result.findings = @[]
  let (fwd, rev) = buildAdjacency(inp)

  # Normalize initial/terminal to base names (input stores them as user-written).
  let initialBases = inp.initialStates.mapIt(extractBaseName(it))
  let terminalBases = inp.terminalStates.mapIt(extractBaseName(it))

  # 1. Determine effective initial set: explicit if provided, else implicit
  #    (states with no incoming edges).
  var initials: seq[string]
  if initialBases.len > 0:
    initials = initialBases
    result.implicitInitialFallback = false
  else:
    initials = @[]
    for s in inp.states:
      if rev.getOrDefault(s, @[]).len == 0:
        initials.add s
    result.implicitInitialFallback = true
  result.initialStatesUsed = initials
  result.terminalStatesUsed = terminalBases

  # 2. No-entry-point case: every state has incoming, no implicit initials.
  if initials.len == 0:
    result.findings.add ReachabilityFinding(
      kind: rfNoEntryPoint, stateName: "", typestateName: inp.typestateName
    )
    return

  # 3. Dead states: unreachable from any initial. A state with no incoming
  #    edges and not declared `initial:` is reported as an orphan instead
  #    (more specific finding — orphans need a different fix from dead
  #    states reachable only via other dead states).
  let reachable = bfs(fwd, initials)
  for s in inp.states:
    if s notin reachable:
      let isOrphan = rev.getOrDefault(s, @[]).len == 0 and s notin initials
      if isOrphan:
        result.findings.add ReachabilityFinding(
          kind: rfOrphan, stateName: s, typestateName: inp.typestateName
        )
      else:
        result.findings.add ReachabilityFinding(
          kind: rfDead, stateName: s, typestateName: inp.typestateName
        )

  # 4. Trap states: reachable, but cannot reach any terminal. Only meaningful
  #    when `terminal:` is declared.
  if terminalBases.len > 0:
    # A bridge to another typestate is a legitimate exit from this typestate,
    # so seed the backward liveness BFS with bridge sources alongside terminals.
    let bridgeBases = inp.bridgeSources.mapIt(extractBaseName(it))
    let liveSeeds = terminalBases & bridgeBases
    let liveSet = bfs(rev, liveSeeds)
    for s in reachable:
      if s notin liveSet and s notin terminalBases and s notin bridgeBases:
        result.findings.add ReachabilityFinding(
          kind: rfTrap, stateName: s, typestateName: inp.typestateName
        )

proc analyzeReachability*(graph: TypestateGraph): ReachabilityReport =
  ## Compile-time convenience overload that projects a `TypestateGraph`
  ## (used by the macro-side parser) into the runtime-friendly
  ## `ReachabilityInput` and runs the analysis.
  analyzeReachability(fromGraph(graph))

proc formatFinding*(f: ReachabilityFinding, initials, terminals: seq[string]): string =
  ## Format a finding as a multi-line warning string.
  case f.kind
  of rfDead:
    result =
      "Dead state '" & f.stateName & "' in typestate '" & f.typestateName & "'\n" &
      "  Unreachable from any initial state.\n" & "  Initial states: " &
      initials.join(", ") & "\n" & "  Hint: add a transition INTO '" & f.stateName &
      "', remove it from `states`, or declare it `initial:`."
  of rfTrap:
    result =
      "Trap state '" & f.stateName & "' in typestate '" & f.typestateName & "'\n" &
      "  Reachable, but cannot reach any terminal state.\n" & "  Terminal states: " &
      terminals.join(", ") & "\n" & "  Hint: add a transition out of '" & f.stateName &
      "' that reaches a terminal, or declare '" & f.stateName & "' itself terminal."
  of rfOrphan:
    result =
      "Orphan state '" & f.stateName & "' in typestate '" & f.typestateName & "'\n" &
      "  No incoming transitions and not declared `initial:`.\n" &
      "  Hint: declare it `initial:` or add a transition INTO it."
  of rfNoEntryPoint:
    result =
      "Typestate '" & f.typestateName & "' has no entry point.\n" &
      "  Every state has at least one incoming transition (graph is one or more cycles).\n" &
      "  Hint: declare an `initial:` block."

proc toFinding*(
    f: ReachabilityFinding, initials, terminals: seq[string], path: string = ""
): Finding =
  ## Convert a `ReachabilityFinding` into a structured `Finding`.
  ##
  ## The first line of the v0.6 multi-line message becomes `message`; all
  ## subsequent indented lines become `hint` (with the leading two-space
  ## indent stripped). `formatHuman(toFinding(rf, …))` reproduces the v0.6
  ## `formatFinding(rf, …)` output verbatim — this is the round-trip
  ## property tested in `tcli_verify_warnings.nim`.
  case f.kind
  of rfDead:
    let message =
      "Dead state '" & f.stateName & "' in typestate '" & f.typestateName & "'"
    let hint =
      "Unreachable from any initial state.\n" & "Initial states: " & initials.join(", ") &
      "\n" & "Hint: add a transition INTO '" & f.stateName &
      "', remove it from `states`, or declare it `initial:`."
    result = mkWarning(fcUnreachableState, path, 0, message, hint)
  of rfTrap:
    let message =
      "Trap state '" & f.stateName & "' in typestate '" & f.typestateName & "'"
    let hint =
      "Reachable, but cannot reach any terminal state.\n" & "Terminal states: " &
      terminals.join(", ") & "\n" & "Hint: add a transition out of '" & f.stateName &
      "' that reaches a terminal, or declare '" & f.stateName & "' itself terminal."
    result = mkWarning(fcNonTerminalState, path, 0, message, hint)
  of rfOrphan:
    let message =
      "Orphan state '" & f.stateName & "' in typestate '" & f.typestateName & "'"
    let hint =
      "No incoming transitions and not declared `initial:`.\n" &
      "Hint: declare it `initial:` or add a transition INTO it."
    result = mkWarning(fcOrphanState, path, 0, message, hint)
  of rfNoEntryPoint:
    let message = "Typestate '" & f.typestateName & "' has no entry point."
    let hint =
      "Every state has at least one incoming transition (graph is one or more cycles).\n" &
      "Hint: declare an `initial:` block."
    result = mkWarning(fcNoEntryPoint, path, 0, message, hint)
