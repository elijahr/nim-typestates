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

import std/[os, strutils, tables, strformat]
import ast_parser

# Re-export types from ast_parser for API compatibility
export ParsedBridge, ParsedTransition, ParsedTypestate, ParseResult, ParseError

type
  SplineMode* = enum
    ## Edge routing mode for DOT output.
    smSpline = "spline"   ## Curved splines (default, best edge separation)
    smOrtho = "ortho"     ## Right-angle edges only
    smPolyline = "polyline" ## Straight line segments
    smLine = "line"       ## Direct straight lines

  EdgeInfo = object
    fromState: string
    toState: string
    isWildcard: bool
    headPort: string  # Compass point for arrow head (only used with non-ortho splines)

  VerifyResult* = object
    ## Results from verifying source files.
    ##
    ## :var errors: List of error messages
    ## :var warnings: List of warning messages
    ## :var transitionsChecked: Count of transitions validated
    ## :var filesChecked: Count of files processed
    errors*: seq[string]
    warnings*: seq[string]
    transitionsChecked*: int
    filesChecked*: int

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
          fromState: trans.fromState,
          toState: toState,
          isWildcard: false,
          headPort: ""
        )

  # Add wildcard edges (skip if explicit exists)
  for trans in ts.transitions:
    if trans.isWildcard:
      for fromState in ts.states:
        for toState in trans.toStates:
          if (fromState, toState) notin explicitEdges:
            allEdges.add EdgeInfo(
              fromState: fromState,
              toState: toState,
              isWildcard: true,
              headPort: ""
            )

  # Assign compass points if enabled
  if useCompassPoints:
    # Count incoming edges per node
    var incomingCount: Table[string, int]
    for edge in allEdges:
      incomingCount.mgetOrPut(edge.toState, 0).inc

    # Assign compass points to nodes with multiple incoming edges
    var incomingIndex: Table[string, int]

    for i in 0..<allEdges.len:
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
  let target = if edge.headPort.len > 0:
    edge.toState & ":" & edge.headPort
  else:
    edge.toState

  if edge.isWildcard:
    if noStyle:
      result = indent & edge.fromState & " -> " & target & " [style=dotted];"
    else:
      result = indent & edge.fromState & " -> " & target & " [style=dotted, color=\"#757575\"];"
  else:
    result = indent & edge.fromState & " -> " & target & ";"

proc generateDot*(ts: ParsedTypestate, noStyle: bool = false, splineMode: SplineMode = smSpline): string =
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
    lines.add "  node [shape=box, style=\"rounded,filled\", fillcolor=\"#2d2d2d\", color=\"#b39ddb\", fontcolor=\"#e0e0e0\", fontname=\"" & fontStack & "\", fontsize=14, margin=\"0.4,0.3\"];"
    lines.add "  edge [fontname=\"" & fontStack & "\", fontsize=11, color=\"#b0b0b0\"];"
    lines.add ""

  # Add nodes
  for state in ts.states:
    lines.add "  " & state & ";"

  lines.add ""

  # Add edges
  let edges = computeEdges(ts, useCompassPoints)
  for edge in edges:
    lines.add formatEdge(edge, "  ", noStyle)

  lines.add "}"
  result = lines.join("\n")

proc generateUnifiedDot*(typestates: seq[ParsedTypestate], noStyle: bool = false, splineMode: SplineMode = smSpline): string =
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
    lines.add "  node [shape=box, style=\"rounded,filled\", fillcolor=\"#2d2d2d\", color=\"#b39ddb\", fontcolor=\"#e0e0e0\", fontname=\"" & fontStack & "\", fontsize=14, margin=\"0.4,0.3\"];"
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
      lines.add "    " & state & ";"

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
        # Use fullDestRepr for complete destination representation (includes module if present)
        let toState = bridge.fullDestRepr

        if fromState == "*":
          # Wildcard bridge: add edge from every state
          for state in ts.states:
            if noStyle:
              lines.add "  " & state & " -> " & toState & " [style=dashed];"
            else:
              lines.add "  " & state & " -> " & toState & " [style=dashed, color=\"#b39ddb\", penwidth=1.5];"
        else:
          if noStyle:
            lines.add "  " & fromState & " -> " & toState & " [style=dashed];"
          else:
            lines.add "  " & fromState & " -> " & toState & " [style=dashed, color=\"#b39ddb\", penwidth=1.5];"

  lines.add "}"
  result = lines.join("\n")

proc generateSeparateDot*(ts: ParsedTypestate, noStyle: bool = false, splineMode: SplineMode = smSpline): string =
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
    lines.add "  node [shape=box, style=\"rounded,filled\", fillcolor=\"#2d2d2d\", color=\"#b39ddb\", fontcolor=\"#e0e0e0\", fontname=\"" & fontStack & "\", fontsize=14, margin=\"0.4,0.3\"];"
    lines.add "  edge [fontname=\"" & fontStack & "\", fontsize=11, color=\"#b0b0b0\"];"
    lines.add ""

  # Add nodes for actual states
  for state in ts.states:
    lines.add "  " & state & ";"

  lines.add ""

  # Add edges
  let edges = computeEdges(ts, useCompassPoints)
  for edge in edges:
    lines.add formatEdge(edge, "  ", noStyle)

  # Add edges for bridges (to terminal nodes)
  for bridge in ts.bridges:
    let fromState = bridge.fromState
    # Use fullDestRepr for complete destination representation (includes module if present)
    let toNode = "\"" & bridge.fullDestRepr & "\""

    if fromState == "*":
      # Wildcard bridge: add edge from every state
      for state in ts.states:
        if noStyle:
          lines.add "  " & state & " -> " & toNode & " [style=dashed];"
        else:
          lines.add "  " & state & " -> " & toNode & " [style=dashed, color=\"#b39ddb\", penwidth=1.5];"
    else:
      if noStyle:
        lines.add "  " & fromState & " -> " & toNode & " [style=dashed];"
      else:
        lines.add "  " & fromState & " -> " & toNode & " [style=dashed, color=\"#b39ddb\", penwidth=1.5];"

  lines.add "}"
  result = lines.join("\n")

proc verifyFile(path: string, typestateStates: Table[string, seq[string]],
                typestateStrict: Table[string, bool]): VerifyResult =
  ## Verify procs in a file against known typestates.
  ##
  ## :param path: Path to the Nim source file
  ## :param typestateStates: Map of typestate name to state names
  ## :param typestateStrict: Map of typestate name to strictTransitions flag
  ## :returns: Verification results with errors and warnings
  result = VerifyResult()
  result.filesChecked = 1

  if not fileExists(path):
    result.errors.add "File not found: " & path
    return

  let content = readFile(path)
  let lines = content.splitLines()

  for i, line in lines:
    let trimmed = line.strip()

    if trimmed.startsWith("proc ") or trimmed.startsWith("func "):
      let hasTransition = "{.transition.}" in trimmed or "{. transition .}" in trimmed
      let hasNotATransition = "{.notATransition.}" in trimmed or "{. notATransition .}" in trimmed

      if "(" in trimmed and ":" in trimmed:
        let paramsPart = trimmed.split("(")[1].split(")")[0]
        if ":" in paramsPart:
          let firstParamType = paramsPart.split(":")[1].split(",")[0].split(")")[0].strip()

          for tsName, states in typestateStates:
            if firstParamType in states:
              if not hasTransition and not hasNotATransition:
                if typestateStrict.getOrDefault(tsName, true):
                  result.errors.add fmt"{path}:{i+1} - Unmarked proc on state '{firstParamType}' (strictTransitions enabled)"
                else:
                  result.warnings.add fmt"{path}:{i+1} - Unmarked proc on state '{firstParamType}'"
              else:
                result.transitionsChecked += 1

proc verify*(paths: seq[string]): VerifyResult =
  ## Verify all Nim files in the given paths.
  ##
  ## Uses Nim's AST parser to extract typestates, then checks that all
  ## procs operating on state types are properly marked with
  ## `{.transition.}` or `{.notATransition.}`.
  ##
  ## **Note:** Files with syntax errors cause verification to fail
  ## immediately with a clear error message.
  ##
  ## :param paths: List of file or directory paths to verify
  ## :returns: Verification results with errors, warnings, and counts
  ## :raises ParseError: on syntax errors
  result = VerifyResult()

  # First pass: collect all typestates using AST parser
  let parseResult = parseTypestates(paths)
  var typestateStates: Table[string, seq[string]]
  var typestateStrict: Table[string, bool]

  for ts in parseResult.typestates:
    typestateStates[ts.name] = ts.states
    typestateStrict[ts.name] = ts.strictTransitions

  # Second pass: verify procs
  for path in paths:
    if path.endsWith(".nim"):
      let fileResult = verifyFile(path, typestateStates, typestateStrict)
      result.errors.add fileResult.errors
      result.warnings.add fileResult.warnings
      result.transitionsChecked += fileResult.transitionsChecked
      result.filesChecked += fileResult.filesChecked
    elif dirExists(path):
      for file in walkDirRec(path):
        if file.endsWith(".nim"):
          let fileResult = verifyFile(file, typestateStates, typestateStrict)
          result.errors.add fileResult.errors
          result.warnings.add fileResult.warnings
          result.transitionsChecked += fileResult.transitionsChecked
          result.filesChecked += fileResult.filesChecked
