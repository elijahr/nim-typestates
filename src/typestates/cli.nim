## Command-line tool for typestates.
##
## Usage:
##
## ```nim
## typestates verify [paths...]
## typestates dot [paths...]
## ```
##
## Parses source files using Nim's AST parser and verifies typestate rules
## or generates DOT output.
##
## **Note:** Files must be valid Nim syntax. Parse errors cause verification
## to fail loudly with a clear error message.

import std/[os, sequtils, sets, strutils, tables, strformat]
import compiler/ast
import ast_parser
import types
import reachability
import lint_opaque_states
import findings

# Re-export types from ast_parser for API compatibility
export ParsedBridge, ParsedTransition, ParsedTypestate, ParseResult, ParseError

# Re-export structured-finding API so `import typestates/cli` callers reach
# `Finding`, `Severity`, `formatHuman`, etc. without a second import.
export findings

type
  SplineMode* = enum
    ## Edge routing mode for DOT output.
    smSpline = "spline" ## Curved splines (default, best edge separation)
    smOrtho = "ortho" ## Right-angle edges only
    smPolyline = "polyline" ## Straight line segments
    smLine = "line" ## Direct straight lines

  EdgeInfo = object
    fromState: string
    toState: string
    isWildcard: bool
    headPort: string # Compass point for arrow head (only used with non-ortho splines)

# `VerifyResult` is defined in `findings.nim` and re-exported above. It now
# carries `findings: seq[Finding]` instead of the v0.6 `errors: seq[string]` /
# `warnings: seq[string]`. Use the `errors()` / `warnings()` accessors or
# `anyErrors`/`anyWarnings` to query.

proc dotQuote(s: string): string =
  ## Quote a string for DOT if it contains special characters.
  ## DOT identifiers with brackets, dots, etc. need to be quoted.
  if '[' in s or ']' in s or '.' in s or ' ' in s or '-' in s:
    result = "\"" & s & "\""
  else:
    result = s

proc parseTypestates*(paths: seq[string]): ParseResult =
  ## Parse all Nim files in the given paths for typestates.
  ##
  ## Uses Nim's AST parser for accurate extraction. Fails loudly on
  ## files with syntax errors.
  ##
  ## :param paths: List of file or directory paths to scan
  ## :returns: All parsed typestates and total file count
  ## :raises ParseError: on syntax errors
  result = parseTypestatesAst(paths)

proc computeEdges(ts: ParsedTypestate, useCompassPoints: bool): seq[EdgeInfo] =
  ## Compute all edges with wildcard deduplication and optional compass points.
  ##
  ## Explicit edges take precedence over wildcard-expanded edges.
  ## If an explicit edge exists, the wildcard version is skipped.
  ##
  ## When useCompassPoints is true, edges to nodes with multiple incoming
  ## edges are distributed across compass points for better separation.
  ##
  ## :param ts: The parsed typestate
  ## :param useCompassPoints: Whether to assign compass points for edge distribution
  ## :returns: Sequence of deduplicated edges

  # Compass points for incoming edges (for TB layout, prefer sides over top)
  const compassPoints = ["e", "w", "s", "se", "sw"]

  var explicitEdges: seq[(string, string)] = @[]
  var allEdges: seq[EdgeInfo] = @[]

  # Collect explicit edges first
  for trans in ts.transitions:
    if not trans.isWildcard:
      for toState in trans.toStates:
        explicitEdges.add (trans.fromState, toState)
        allEdges.add EdgeInfo(
          fromState: trans.fromState, toState: toState, isWildcard: false, headPort: ""
        )

  # Add wildcard edges (skip if explicit exists)
  for trans in ts.transitions:
    if trans.isWildcard:
      for fromState in ts.states:
        for toState in trans.toStates:
          if (fromState, toState) notin explicitEdges:
            allEdges.add EdgeInfo(
              fromState: fromState, toState: toState, isWildcard: true, headPort: ""
            )

  # Assign compass points if enabled
  if useCompassPoints:
    # Count incoming edges per node
    var incomingCount: Table[string, int]
    for edge in allEdges:
      incomingCount.mgetOrPut(edge.toState, 0).inc

    # Assign compass points to nodes with multiple incoming edges
    var incomingIndex: Table[string, int]

    for i in 0 ..< allEdges.len:
      let toState = allEdges[i].toState
      let fromState = allEdges[i].fromState

      if fromState == toState:
        # Self-loop: use east side
        allEdges[i].headPort = "e"
      elif incomingCount.getOrDefault(toState, 0) > 1:
        # Multiple incoming edges: distribute across compass points
        let idx = incomingIndex.mgetOrPut(toState, 0)
        allEdges[i].headPort = compassPoints[idx mod compassPoints.len]
        incomingIndex[toState] = idx + 1

  result = allEdges

proc formatEdge(edge: EdgeInfo, indent: string, noStyle: bool): string =
  ## Format a single edge as DOT syntax.
  ##
  ## :param edge: The edge info (may include compass point in headPort)
  ## :param indent: Indentation string (e.g., "  " or "    ")
  ## :param noStyle: If true, use minimal styling (dotted style only, no colors)
  ## :returns: DOT edge statement
  let fromQuoted = dotQuote(edge.fromState)
  let toQuoted = dotQuote(edge.toState)
  let target =
    if edge.headPort.len > 0:
      toQuoted & ":" & edge.headPort
    else:
      toQuoted

  if edge.isWildcard:
    if noStyle:
      result = indent & fromQuoted & " -> " & target & " [style=dotted];"
    else:
      result =
        indent & fromQuoted & " -> " & target & " [style=dotted, color=\"#757575\"];"
  else:
    result = indent & fromQuoted & " -> " & target & ";"

proc generateDot*(
    ts: ParsedTypestate, noStyle: bool = false, splineMode: SplineMode = smSpline
): string =
  ## Generate GraphViz DOT output for a typestate.
  ##
  ## Creates a directed graph representation suitable for rendering
  ## with `dot`, `neato`, or other GraphViz tools.
  ##
  ## :param ts: The parsed typestate to visualize
  ## :param noStyle: If true, output bare DOT structure with no styling
  ## :param splineMode: Edge routing mode (spline, ortho, polyline, line)
  ## :returns: DOT format string
  var lines: seq[string] = @[]

  lines.add "digraph " & ts.name & " {"

  # Compass points only work with non-ortho splines
  # ordering=out crashes when combined with compass points, so only use it with ortho
  let useCompassPoints = splineMode != smOrtho

  if not noStyle:
    const fontStack = "sans-serif"
    lines.add "  rankdir=TB;"
    lines.add "  splines=" & $splineMode & ";"
    lines.add "  nodesep=1.0;"
    lines.add "  ranksep=1.0;"
    if splineMode == smOrtho:
      lines.add "  ordering=out;"
    lines.add "  bgcolor=\"transparent\";"
    lines.add "  pad=0.3;"
    lines.add ""
    lines.add "  node [shape=box, style=\"rounded,filled\", fillcolor=\"#2d2d2d\", color=\"#b39ddb\", fontcolor=\"#e0e0e0\", fontname=\"" &
      fontStack & "\", fontsize=14, margin=\"0.4,0.3\"];"
    lines.add "  edge [fontname=\"" & fontStack & "\", fontsize=11, color=\"#b0b0b0\"];"
    lines.add ""

  # Add nodes
  for state in ts.states:
    lines.add "  " & dotQuote(state) & ";"

  lines.add ""

  # Add edges
  let edges = computeEdges(ts, useCompassPoints)
  for edge in edges:
    lines.add formatEdge(edge, "  ", noStyle)

  lines.add "}"
  result = lines.join("\n")

proc generateUnifiedDot*(
    typestates: seq[ParsedTypestate],
    noStyle: bool = false,
    splineMode: SplineMode = smSpline,
): string =
  ## Generate a unified GraphViz DOT output showing all typestates.
  ##
  ## Creates subgraphs for each typestate with cross-cluster edges for bridges.
  ##
  ## :param typestates: List of parsed typestates to visualize
  ## :param noStyle: If true, output bare DOT structure with no styling
  ## :param splineMode: Edge routing mode (spline, ortho, polyline, line)
  ## :returns: DOT format string
  var lines: seq[string] = @[]

  # Compass points only work with non-ortho splines
  # ordering=out crashes when combined with compass points, so only use it with ortho
  let useCompassPoints = splineMode != smOrtho

  lines.add "digraph {"

  if not noStyle:
    const fontStack = "sans-serif"
    lines.add "  rankdir=TB;"
    lines.add "  splines=" & $splineMode & ";"
    lines.add "  compound=true;"
    lines.add "  nodesep=1.0;"
    lines.add "  ranksep=1.0;"
    if splineMode == smOrtho:
      lines.add "  ordering=out;"
    lines.add "  bgcolor=\"transparent\";"
    lines.add "  pad=0.3;"
    lines.add ""
    lines.add "  node [shape=box, style=\"rounded,filled\", fillcolor=\"#2d2d2d\", color=\"#b39ddb\", fontcolor=\"#e0e0e0\", fontname=\"" &
      fontStack & "\", fontsize=14, margin=\"0.4,0.3\"];"
    lines.add "  edge [fontname=\"" & fontStack & "\", fontsize=11, color=\"#b0b0b0\"];"
    lines.add ""

  # Generate subgraphs for each typestate
  for ts in typestates:
    lines.add "  subgraph cluster_" & ts.name & " {"
    lines.add "    label=\"" & ts.name & "\";"

    if not noStyle:
      const fontStack = "sans-serif"
      lines.add "    fontname=\"" & fontStack & "\";"
      lines.add "    fontsize=16;"
      lines.add "    fontcolor=\"#e0e0e0\";"
      lines.add "    labelloc=t;"
      lines.add "    style=\"rounded\";"
      lines.add "    color=\"#b39ddb\";"
      lines.add "    bgcolor=\"#1e1e1e\";"
      lines.add "    margin=30;"

    lines.add ""

    # Add nodes
    for state in ts.states:
      lines.add "    " & dotQuote(state) & ";"

    lines.add ""

    # Add edges
    let edges = computeEdges(ts, useCompassPoints)
    for edge in edges:
      lines.add formatEdge(edge, "    ", noStyle)

    lines.add "  }"
    lines.add ""

  # Add bridges (cross-cluster edges)
  var hasBridges = false
  for ts in typestates:
    if ts.bridges.len > 0:
      hasBridges = true
      break

  if hasBridges:
    lines.add "  // Bridges (cross-typestate)"
    for ts in typestates:
      for bridge in ts.bridges:
        let fromState = bridge.fromState
        let fromQuoted = dotQuote(fromState)
        # Use fullDestRepr for complete destination representation (includes module if present)
        let toState = bridge.fullDestRepr

        # Quote toState for DOT compatibility (handles dots in module.Type.State)
        let quotedToState = "\"" & toState & "\""
        if fromState == "*":
          # Wildcard bridge: add edge from every state
          for state in ts.states:
            let stateQuoted = dotQuote(state)
            if noStyle:
              lines.add "  " & stateQuoted & " -> " & quotedToState & " [style=dashed];"
            else:
              lines.add "  " & stateQuoted & " -> " & quotedToState &
                " [style=dashed, color=\"#b39ddb\", penwidth=1.5];"
        else:
          if noStyle:
            lines.add "  " & fromQuoted & " -> " & quotedToState & " [style=dashed];"
          else:
            lines.add "  " & fromQuoted & " -> " & quotedToState &
              " [style=dashed, color=\"#b39ddb\", penwidth=1.5];"

  lines.add "}"
  result = lines.join("\n")

proc generateSeparateDot*(
    ts: ParsedTypestate, noStyle: bool = false, splineMode: SplineMode = smSpline
): string =
  ## Generate GraphViz DOT output for a single typestate.
  ##
  ## Bridges are shown as terminal nodes with dashed edges.
  ##
  ## :param ts: The parsed typestate to visualize
  ## :param noStyle: If true, output bare DOT structure with no styling
  ## :param splineMode: Edge routing mode (spline, ortho, polyline, line)
  ## :returns: DOT format string
  var lines: seq[string] = @[]

  # Compass points only work with non-ortho splines
  # ordering=out crashes when combined with compass points, so only use it with ortho
  let useCompassPoints = splineMode != smOrtho

  lines.add "digraph " & ts.name & " {"

  if not noStyle:
    const fontStack = "sans-serif"
    lines.add "  rankdir=TB;"
    lines.add "  splines=" & $splineMode & ";"
    lines.add "  nodesep=1.0;"
    lines.add "  ranksep=1.0;"
    if splineMode == smOrtho:
      lines.add "  ordering=out;"
    lines.add "  bgcolor=\"transparent\";"
    lines.add "  pad=0.3;"
    lines.add ""
    lines.add "  node [shape=box, style=\"rounded,filled\", fillcolor=\"#2d2d2d\", color=\"#b39ddb\", fontcolor=\"#e0e0e0\", fontname=\"" &
      fontStack & "\", fontsize=14, margin=\"0.4,0.3\"];"
    lines.add "  edge [fontname=\"" & fontStack & "\", fontsize=11, color=\"#b0b0b0\"];"
    lines.add ""

  # Add nodes for actual states
  for state in ts.states:
    lines.add "  " & dotQuote(state) & ";"

  lines.add ""

  # Add edges
  let edges = computeEdges(ts, useCompassPoints)
  for edge in edges:
    lines.add formatEdge(edge, "  ", noStyle)

  # Add edges for bridges (to terminal nodes)
  for bridge in ts.bridges:
    let fromState = bridge.fromState
    let fromQuoted = dotQuote(fromState)
    # Use fullDestRepr for complete destination representation (includes module if present)
    let toNode = "\"" & bridge.fullDestRepr & "\""

    if fromState == "*":
      # Wildcard bridge: add edge from every state
      for state in ts.states:
        let stateQuoted = dotQuote(state)
        if noStyle:
          lines.add "  " & stateQuoted & " -> " & toNode & " [style=dashed];"
        else:
          lines.add "  " & stateQuoted & " -> " & toNode &
            " [style=dashed, color=\"#b39ddb\", penwidth=1.5];"
    else:
      if noStyle:
        lines.add "  " & fromQuoted & " -> " & toNode & " [style=dashed];"
      else:
        lines.add "  " & fromQuoted & " -> " & toNode &
          " [style=dashed, color=\"#b39ddb\", penwidth=1.5];"

  lines.add "}"
  result = lines.join("\n")

proc branchEnumPrefix(typeName: string): string =
  ## Generate a short prefix for branch enum fields.
  if typeName.len > 0:
    result = ($typeName[0]).toLowerAscii()
  else:
    result = "b"

proc generateCode*(ts: ParsedTypestate): string =
  ## Generate Nim code for a typestate's helper types and procs.
  ##
  ## Generates:
  ## - State enum (`FileState = enum fsClosed, fsOpen, ...`)
  ## - Union type (`FileStates = Closed | Open | ...`)
  ## - State procs (`proc state(f: Closed): FileState`)
  ## - Branch types for branching transitions
  ## - Branch constructors and operators
  ##
  ## :param ts: The parsed typestate to generate code for
  ## :returns: Generated Nim code as a string
  var lines: seq[string] = @[]

  lines.add "# Generated code for typestate: " & ts.name
  lines.add ""

  # 1. Generate state enum
  let enumName = ts.name & "State"
  var enumFields: seq[string] = @[]
  for state in ts.states:
    let baseName = state.split("[")[0] # Handle generics: Empty[T] -> Empty
    enumFields.add "fs" & baseName

  lines.add "type"
  lines.add "  " & enumName & "* = enum"
  lines.add "    " & enumFields.join(", ")
  lines.add ""

  # 2. Generate union type
  let unionName = ts.name & "States"
  lines.add "type"
  lines.add "  " & unionName & "* = " & ts.states.join(" | ")
  lines.add ""

  # 3. Generate state procs
  for state in ts.states:
    let baseName = state.split("[")[0]
    let enumField = "fs" & baseName
    lines.add "proc state*(f: " & state & "): " & enumName & " = " & enumField
  lines.add ""

  # 4. Generate branch types for branching transitions
  var branchingTransitions: seq[ParsedTransition] = @[]
  for t in ts.transitions:
    if t.toStates.len > 1 and not t.isWildcard:
      branchingTransitions.add t

  for t in branchingTransitions:
    # Extract branch type name from the transition
    # For now, use the source state + "Result" as the branch type name
    let fromBase = t.fromState.split("[")[0]
    let branchTypeName = fromBase & "Result"
    let kindTypeName = branchTypeName & "Kind"
    let prefix = branchEnumPrefix(branchTypeName)

    # Generate enum
    var kindFields: seq[string] = @[]
    for dest in t.toStates:
      let destBase = dest.split("[")[0]
      kindFields.add prefix & destBase

    lines.add "type"
    lines.add "  " & kindTypeName & "* = enum"
    lines.add "    " & kindFields.join(", ")
    lines.add ""

    # Generate object variant
    lines.add "  " & branchTypeName & "* = object"
    lines.add "    case kind*: " & kindTypeName

    for i, dest in t.toStates:
      let destBase = dest.split("[")[0]
      let fieldName = destBase.toLowerAscii()
      let kindField = kindFields[i]
      lines.add "    of " & kindField & ":"
      lines.add "      " & fieldName & "*: " & dest

    lines.add ""

    # Generate constructors
    for i, dest in t.toStates:
      let destBase = dest.split("[")[0]
      let fieldName = destBase.toLowerAscii()
      let kindField = kindFields[i]
      let procName = "to" & branchTypeName

      lines.add "proc " & procName & "*(s: sink " & dest & "): " & branchTypeName & " ="
      lines.add "  " & branchTypeName & "(kind: " & kindField & ", " & fieldName & ": s)"
      lines.add ""

    # Generate -> operator
    for i, dest in t.toStates:
      let procName = "to" & branchTypeName

      lines.add "template `->`*(_: typedesc[" & branchTypeName & "], s: sink " & dest &
        "): " & branchTypeName & " ="
      lines.add "  " & procName & "(s)"
      lines.add ""

  result = lines.join("\n")

proc generateCodeForAll*(typestates: seq[ParsedTypestate]): string =
  ## Generate code for all typestates.
  ##
  ## :param typestates: All parsed typestates
  ## :returns: Combined generated Nim code
  var sections: seq[string] = @[]
  for ts in typestates:
    sections.add generateCode(ts)
  result = sections.join("\n\n")

proc verifyFile(
    path: string,
    tree: PNode,
    registeredStateBases: HashSet[string],
    stateBaseStrict: Table[string, bool],
): VerifyResult =
  ## Verify the routines of a single already-parsed file against the registered
  ## typestate states using compiler-AST classification.
  ##
  ## Tier-B: the caller (`verify()`) supplies the file's parsed `PNode` tree
  ## (shared with Pass 1) so this proc never re-reads or re-parses the file.
  ## `classifyProcsInFile` collects every routine with at least one
  ## typestate-state parameter; for each such routine we either flag an unmarked
  ## proc (error on strict, warning otherwise) or, when it carries a
  ## `{.transition.}` / `{.notATransition.}` marker, count it once toward
  ## `transitionsChecked`.
  ##
  ## Replaces the v0.9.3 line-based substring scanner, which silently missed
  ## multi-line proc headers, combined pragma blocks, and `var`/`sink`/`ptr`/
  ## `ref`/generic parameter types.
  ##
  ## :param path: Source file path (used only for `Finding.path`).
  ## :param tree: The file's parsed compiler AST (read-only).
  ## :param registeredStateBases: Base names of every typestate state.
  ## :param stateBaseStrict: Per-state-base strictTransitions flag (default
  ##   `true` when a base is absent), used to route severity.
  ## :returns: Verification results with structured findings.
  result = VerifyResult()
  result.filesChecked = 1

  for cp in classifyProcsInFile(tree, registeredStateBases):
    case cp.class
    of pcTransition, pcNotATransition:
      # Marked routine: count once per proc, regardless of how many state
      # params it carries (count-once-per-proc semantics).
      result.transitionsChecked += 1
    of pcUnmarked:
      # Anchor the finding to the first matched state base, mirroring the
      # old scanner's "first typestate param type" reporting.
      let base = cp.paramStateBases[0]
      if stateBaseStrict.getOrDefault(base, true):
        result.findings.add mkError(
          fcUnmarkedProcStrict,
          path,
          cp.line,
          fmt"Unmarked proc on state '{base}' (strictTransitions enabled)",
          column = cp.column,
        )
      else:
        result.findings.add mkWarning(
          fcUnmarkedProc,
          path,
          cp.line,
          fmt"Unmarked proc on state '{base}'",
          column = cp.column,
        )

proc parsedToReachabilityInput(pt: ParsedTypestate): ReachabilityInput =
  ## Project a CLI-parsed typestate into the runtime-friendly graph view
  ## consumed by `analyzeReachability`. Only state base names and transition
  ## edges are required; the analyzer does not consult `NimNode` fields.
  result.typestateName = pt.name
  result.states = pt.states.mapIt(extractBaseName(it))
  result.edges = @[]
  for t in pt.transitions:
    var e: GraphEdge
    e.fromState = extractBaseName(t.fromState)
    e.toStates = t.toStates.mapIt(extractBaseName(it))
    e.isWildcard = t.isWildcard
    result.edges.add e
  result.initialStates = pt.initialStates.mapIt(extractBaseName(it))
  result.terminalStates = pt.terminalStates.mapIt(extractBaseName(it))
  result.bridgeSources = @[]
  for b in pt.bridges:
    result.bridgeSources.add extractBaseName(b.fromState)

proc verify*(paths: seq[string]): VerifyResult =
  ## Verify all Nim files in the given paths.
  ##
  ## Uses Nim's AST parser to extract typestates, then checks that all
  ## procs operating on state types are properly marked with
  ## `{.transition.}` or `{.notATransition.}`. Also runs reachability
  ## analysis when `initial:` / `terminal:` blocks are declared and the
  ## opaque-states cast-bypass lint, appending all results to
  ## `result.findings`.
  ##
  ## Files with syntax errors no longer abort the pipeline: they surface as
  ## `fcParseError` findings routed through the normal output formatters.
  ## A parse error in one file does NOT abort verification of other files —
  ## `typestates verify --format=github src/` produces annotations for
  ## every problem the user has, not just the first.
  ##
  ## :param paths: List of file or directory paths to verify
  ## :returns: Verification results with structured findings and counts
  result = VerifyResult()

  # File-not-found (RC-2): an explicit `.nim` path that does not exist is a
  # distinct, user-actionable error code (`fcFileNotFound`), not a parse
  # error. Detect these BEFORE parsing so the dedicated code/message is
  # preserved and the missing file is excluded from the shared parse (whose
  # `parsePNode` would otherwise record it as a generic `fcParseError`).
  var notFoundPaths = initHashSet[string]()
  for path in paths:
    if path.endsWith(".nim") and not fileExists(path):
      result.findings.add mkError(fcFileNotFound, path, 0, "File not found: " & path)
      notFoundPaths.incl(absolutePath(path))

  # First pass (Tier B): parse every file EXACTLY ONCE. The parsed `PNode`
  # trees are retained in `project.nodes` (keyed by absolute path) so the
  # proc-classification pass below reuses them instead of re-reading and
  # re-parsing. Per-file parse errors are accumulated into
  # `project.parse.failures` rather than raised; convert each one to an
  # `fcParseError` Finding so `--format=github`/`--format=json` consumers
  # still receive structured output for every malformed input.
  let project = parseTypestatesAstWithNodes(paths)
  let parseResult = project.parse
  var failedPaths = initHashSet[string]()
  for f in parseResult.failures:
    # Skip failures for paths already reported as file-not-found above so the
    # missing file is reported once, with the dedicated code.
    if f.path.len > 0 and absolutePath(f.path) in notFoundPaths:
      continue
    result.findings.add mkError(
      fcParseError, f.path, f.line, f.message, column = f.column
    )
    # Track absolute path so pass 3 (opaque-states lint) can skip the same
    # file without emitting duplicate parse-error findings.
    if f.path.len > 0:
      failedPaths.incl(absolutePath(f.path))

  # Build the registered-state view shared by the classification pass:
  #  - `registeredStateBases`: base names of every typestate state, so a proc
  #    param resolves to a state regardless of generics/var/ptr/ref wrapping.
  #  - `stateBaseStrict`: per-state-base strictTransitions flag. On a base-name
  #    collision across typestates, prefer flagging if ANY owner is strict
  #    (preserves the old default-strict spirit). Absent base => default true.
  var registeredStateBases = initHashSet[string]()
  var stateBaseStrict = initTable[string, bool]()
  for ts in parseResult.typestates:
    for state in ts.states:
      let base = extractBaseName(state)
      registeredStateBases.incl(base)
      if base in stateBaseStrict:
        stateBaseStrict[base] = stateBaseStrict[base] or ts.strictTransitions
      else:
        stateBaseStrict[base] = ts.strictTransitions

  # Reachability/liveness pass: gated on initial:/terminal: declarations to
  # mirror macro-side semantics (no warnings for typestates that haven't
  # opted in).
  for pt in parseResult.typestates:
    if pt.initialStates.len > 0 or pt.terminalStates.len > 0:
      let inp = parsedToReachabilityInput(pt)
      let report = analyzeReachability(inp)
      for f in report.findings:
        result.findings.add toFinding(
          f, report.initialStatesUsed, report.terminalStatesUsed
        )

  # Second pass: classify procs over the shared parse trees. Files that failed
  # to parse have no entry in `project.nodes`, so they are naturally skipped
  # (their `fcParseError` Finding was already emitted above) without a second
  # parse or a duplicate error.
  for filePath, tree in project.nodes:
    let fileResult = verifyFile(filePath, tree, registeredStateBases, stateBaseStrict)
    result.findings.add fileResult.findings
    result.transitionsChecked += fileResult.transitionsChecked
    result.filesChecked += fileResult.filesChecked

  # Pass 3: opaqueStates lint (CLI-side cast-bypass detection). Pass the
  # set of pass-1 failed paths so the lint can skip them without
  # double-reporting parse-error findings already emitted above.
  result.findings.add lintOpaqueStates(parseResult, paths, failedPaths)
