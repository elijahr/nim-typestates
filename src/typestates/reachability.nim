## Reachability and liveness analysis for typestate graphs.
##
## Computes:
## - **Dead states**: unreachable from any initial state.
## - **Trap states**: reachable, but cannot reach any terminal state
##   (only when `terminal:` is declared).
## - **Orphan states**: no incoming transitions and not declared `initial:`
##   (only reported for states that are otherwise reachable, to avoid
##   double-reporting dead states).
## - **No-entry-point**: no `initial:` declared and every state has at
##   least one incoming transition (graph is one or more cycles).
##
## Used by both the macro-side parser (compile-time `warning(...)`
## emission) and the CLI verifier (populates `VerifyResult.warnings`).

import std/[tables, sets, sequtils, strutils]
import types

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

  GraphEdge* = object
    ## A directed edge in a typestate graph, normalized to base names.
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

proc fromGraph*(graph: TypestateGraph): ReachabilityInput =
  ## Project a compile-time `TypestateGraph` into a `ReachabilityInput`.
  result.typestateName = graph.name
  result.states = @[]
  for s in graph.states.keys:
    result.states.add s
  result.edges = @[]
  for t in graph.transitions:
    var e: GraphEdge
    e.fromState = t.fromState
    e.toStates = t.toStates
    e.isWildcard = t.isWildcard
    result.edges.add e
  result.initialStates = graph.initialStates
  result.terminalStates = graph.terminalStates

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
        @[extractBaseName(t.fromState)]
    for src in sources:
      for dst in t.toStates:
        let srcBase = extractBaseName(src)
        let dstBase = extractBaseName(dst)
        if srcBase in result.forward:
          result.forward[srcBase].add dstBase
        if dstBase in result.reverse:
          result.reverse[dstBase].add srcBase

proc bfs(adj: Table[string, seq[string]], starts: seq[string]): HashSet[string] =
  ## Standard BFS reachability over a directed adjacency table.
  result = initHashSet[string]()
  var queue: seq[string] = @[]
  for s in starts:
    if s notin result:
      result.incl s
      queue.add s
  while queue.len > 0:
    let n = queue[0]
    queue.delete(0)
    if n in adj:
      for nbr in adj[n]:
        if nbr notin result:
          result.incl nbr
          queue.add nbr

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

  # 3. Dead states: unreachable from any initial.
  let reachable = bfs(fwd, initials)
  for s in inp.states:
    if s notin reachable:
      result.findings.add ReachabilityFinding(
        kind: rfDead, stateName: s, typestateName: inp.typestateName
      )

  # 4. Trap states: reachable, but cannot reach any terminal. Only meaningful
  #    when `terminal:` is declared.
  if terminalBases.len > 0:
    let liveSet = bfs(rev, terminalBases)
    for s in reachable:
      if s notin liveSet and s notin terminalBases:
        result.findings.add ReachabilityFinding(
          kind: rfTrap, stateName: s, typestateName: inp.typestateName
        )

  # 5. Orphan states: no incoming and not initial. Skip if also unreachable
  #    (already reported as dead).
  for s in inp.states:
    if s in initials:
      continue
    if rev.getOrDefault(s, @[]).len == 0:
      if s notin reachable:
        continue
      result.findings.add ReachabilityFinding(
        kind: rfOrphan, stateName: s, typestateName: inp.typestateName
      )

proc analyzeReachability*(graph: TypestateGraph): ReachabilityReport =
  ## Compile-time convenience overload that projects a `TypestateGraph`
  ## (used by the macro-side parser) into the runtime-friendly
  ## `ReachabilityInput` and runs the analysis.
  analyzeReachability(fromGraph(graph))

proc formatFinding*(
    f: ReachabilityFinding, initials, terminals: seq[string]
): string =
  ## Format a finding as a multi-line warning string.
  case f.kind
  of rfDead:
    result =
      "Dead state '" & f.stateName & "' in typestate '" & f.typestateName & "'\n" &
      "  Unreachable from any initial state.\n" &
      "  Initial states: " & initials.join(", ") & "\n" &
      "  Hint: add a transition INTO '" & f.stateName &
      "', remove it from `states`, or declare it `initial:`."
  of rfTrap:
    result =
      "Trap state '" & f.stateName & "' in typestate '" & f.typestateName & "'\n" &
      "  Reachable, but cannot reach any terminal state.\n" &
      "  Terminal states: " & terminals.join(", ") & "\n" &
      "  Hint: add a transition out of '" & f.stateName &
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
