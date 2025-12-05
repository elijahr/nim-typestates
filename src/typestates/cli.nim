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

proc generateDot*(ts: ParsedTypestate): string =
  ## Generate GraphViz DOT output for a typestate.
  ##
  ## Creates a directed graph representation suitable for rendering
  ## with `dot`, `neato`, or other GraphViz tools.
  ## Uses dark mode styling matching mkdocs-material slate theme.
  ##
  ## Edge styles:
  ## - Normal transitions: solid light gray arrows
  ## - Wildcard transitions (* ->): dotted gray arrows
  ##
  ## :param ts: The parsed typestate to visualize
  ## :returns: DOT format string
  var lines: seq[string] = @[]

  # Font stack: Inter is a modern, highly legible sans-serif
  const fontStack = "Inter, SF Pro Display, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif"

  lines.add "digraph " & ts.name & " {"
  lines.add "  rankdir=LR;"
  lines.add "  bgcolor=\"transparent\";"
  lines.add "  pad=0.5;"
  lines.add ""
  # Node styling: dark mode with light purple accents
  lines.add "  node [shape=box, style=\"rounded,filled\", fillcolor=\"#2d2d2d\", color=\"#b39ddb\", fontcolor=\"#e0e0e0\", fontname=\"" & fontStack & "\", fontsize=11, margin=\"0.2,0.1\"];"
  # Default edge styling: light gray for visibility on dark backgrounds
  lines.add "  edge [fontname=\"" & fontStack & "\", fontsize=9, color=\"#b0b0b0\"];"
  lines.add ""

  # Add nodes
  for state in ts.states:
    lines.add "  " & state & ";"

  lines.add ""

  # Add edges
  for trans in ts.transitions:
    if trans.isWildcard:
      # Wildcard transitions: dotted medium gray
      for fromState in ts.states:
        for toState in trans.toStates:
          lines.add "  " & fromState & " -> " & toState & " [style=dotted, color=\"#757575\"];"
    else:
      for toState in trans.toStates:
        lines.add "  " & trans.fromState & " -> " & toState & ";"

  lines.add "}"
  result = lines.join("\n")

proc generateUnifiedDot*(typestates: seq[ParsedTypestate]): string =
  ## Generate a unified GraphViz DOT output showing all typestates.
  ##
  ## Creates subgraphs for each typestate with cross-cluster edges for bridges.
  ## Uses dark mode styling matching mkdocs-material slate theme.
  ##
  ## Edge styles:
  ## - Normal transitions: solid light gray arrows
  ## - Wildcard transitions (* ->): dotted gray arrows
  ## - Bridges (cross-typestate): dashed light purple arrows
  ##
  ## :param typestates: List of parsed typestates to visualize
  ## :returns: DOT format string
  var lines: seq[string] = @[]

  # Font stack: Inter is a modern, highly legible sans-serif
  const fontStack = "Inter, SF Pro Display, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif"

  lines.add "digraph {"
  lines.add "  rankdir=LR;"
  lines.add "  bgcolor=\"transparent\";"
  lines.add "  pad=0.5;"
  lines.add ""
  # Node styling: dark mode with light purple accents
  lines.add "  node [shape=box, style=\"rounded,filled\", fillcolor=\"#2d2d2d\", color=\"#b39ddb\", fontcolor=\"#e0e0e0\", fontname=\"" & fontStack & "\", fontsize=11, margin=\"0.2,0.1\"];"
  # Default edge styling: light gray for visibility on dark backgrounds
  lines.add "  edge [fontname=\"" & fontStack & "\", fontsize=9, color=\"#b0b0b0\"];"
  lines.add ""

  # Generate subgraphs for each typestate
  for ts in typestates:
    lines.add "  subgraph cluster_" & ts.name & " {"
    lines.add "    label=\"" & ts.name & "\";"
    lines.add "    fontname=\"" & fontStack & "\";"
    lines.add "    fontsize=12;"
    lines.add "    fontcolor=\"#e0e0e0\";"  # Light text for dark mode
    lines.add "    style=\"rounded\";"
    lines.add "    color=\"#b39ddb\";"  # Light purple border
    lines.add "    bgcolor=\"#1e1e1e\";"  # Dark background
    lines.add "    margin=16;"
    lines.add ""

    # Add nodes
    for state in ts.states:
      lines.add "    " & state & ";"

    lines.add ""

    # Add transitions (within this typestate)
    for trans in ts.transitions:
      if trans.isWildcard:
        # Wildcard transitions: dotted medium gray
        for fromState in ts.states:
          for toState in trans.toStates:
            lines.add "    " & fromState & " -> " & toState & " [style=dotted, color=\"#757575\"];"
      else:
        for toState in trans.toStates:
          lines.add "    " & trans.fromState & " -> " & toState & ";"

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
        let toState = bridge.toState

        if fromState == "*":
          # Wildcard bridge: add edge from every state
          for state in ts.states:
            lines.add "  " & state & " -> " & toState & " [style=dashed, color=\"#b39ddb\", penwidth=1.5];"
        else:
          lines.add "  " & fromState & " -> " & toState & " [style=dashed, color=\"#b39ddb\", penwidth=1.5];"

  lines.add "}"
  result = lines.join("\n")

proc generateSeparateDot*(ts: ParsedTypestate): string =
  ## Generate GraphViz DOT output for a single typestate.
  ##
  ## Bridges are shown as terminal nodes with dashed purple edges.
  ## Uses dark mode styling matching mkdocs-material slate theme.
  ##
  ## Edge styles:
  ## - Normal transitions: solid light gray arrows
  ## - Wildcard transitions (* ->): dotted gray arrows
  ## - Bridges (to external typestate): dashed light purple arrows
  ##
  ## :param ts: The parsed typestate to visualize
  ## :returns: DOT format string
  var lines: seq[string] = @[]

  # Font stack: Inter is a modern, highly legible sans-serif
  const fontStack = "Inter, SF Pro Display, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif"

  lines.add "digraph " & ts.name & " {"
  lines.add "  rankdir=LR;"
  lines.add "  bgcolor=\"transparent\";"
  lines.add "  pad=0.5;"
  lines.add ""
  # Node styling: dark mode with light purple accents
  lines.add "  node [shape=box, style=\"rounded,filled\", fillcolor=\"#2d2d2d\", color=\"#b39ddb\", fontcolor=\"#e0e0e0\", fontname=\"" & fontStack & "\", fontsize=11, margin=\"0.2,0.1\"];"
  # Default edge styling: light gray for visibility on dark backgrounds
  lines.add "  edge [fontname=\"" & fontStack & "\", fontsize=9, color=\"#b0b0b0\"];"
  lines.add ""

  # Add nodes for actual states
  for state in ts.states:
    lines.add "  " & state & ";"

  lines.add ""

  # Add edges for transitions
  for trans in ts.transitions:
    if trans.isWildcard:
      # Wildcard transitions: dotted medium gray
      for fromState in ts.states:
        for toState in trans.toStates:
          lines.add "  " & fromState & " -> " & toState & " [style=dotted, color=\"#757575\"];"
    else:
      for toState in trans.toStates:
        lines.add "  " & trans.fromState & " -> " & toState & ";"

  # Add edges for bridges (to terminal nodes)
  for bridge in ts.bridges:
    let fromState = bridge.fromState
    let toNode = "\"" & bridge.toTypestate & "." & bridge.toState & "\""

    if fromState == "*":
      # Wildcard bridge: add edge from every state
      for state in ts.states:
        lines.add "  " & state & " -> " & toNode & " [style=dashed, color=\"#b39ddb\", penwidth=1.5];"
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
