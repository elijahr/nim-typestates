## GraphViz DOT output for typestate visualization.
##
## This module generates GraphViz DOT format output for visualizing
## typestate graphs. The output can be rendered with `dot`, `neato`,
## or any GraphViz-compatible tool.
##
## **Example output:**
## ```dot
## digraph File {
##   rankdir=LR;
##   node [shape=box];
##
##   Closed;
##   Open;
##   Errored;
##
##   Closed -> Open;
##   Closed -> Errored;
##   Open -> Closed;
## }
## ```
##
## **Rendering:**
## ```bash
## dot -Tpng file_typestate.dot -o file_typestate.png
## dot -Tsvg file_typestate.dot -o file_typestate.svg
## ```

import std/[strutils, tables]
import types

proc generateDot*(graph: TypestateGraph): string =
  ## Generate a GraphViz DOT representation of the typestate.
  ##
  ## Creates a directed graph where:
  ## - Nodes are states (rendered as boxes)
  ## - Edges are transitions (solid lines)
  ## - Wildcard transitions are shown as dashed lines
  ##
  ## **Parameters:**
  ## - `graph`: The typestate graph to visualize
  ##
  ## **Returns:** DOT format string
  ##
  ## **Example:**
  ## ```nim
  ## let dot = generateDot(myGraph)
  ## echo dot
  ## # digraph File {
  ## #   rankdir=LR;
  ## #   node [shape=box];
  ## #   ...
  ## # }
  ## ```
  var lines: seq[string] = @[]

  lines.add "digraph " & graph.name & " {"
  lines.add "  rankdir=LR;"
  lines.add "  node [shape=box];"
  lines.add ""

  # Add nodes
  for stateName in graph.states.keys:
    lines.add "  " & stateName & ";"

  lines.add ""

  # Add edges
  for trans in graph.transitions:
    if trans.isWildcard:
      # Expand wildcard to all states
      for fromState in graph.states.keys:
        for toState in trans.toStates:
          lines.add "  " & fromState & " -> " & toState & " [style=dashed];"
    else:
      for toState in trans.toStates:
        lines.add "  " & trans.fromState & " -> " & toState & ";"

  lines.add "}"

  result = lines.join("\n")

proc writeDotFile*(graph: TypestateGraph, filename: string) =
  ## Write the DOT representation to a file.
  ##
  ## Convenience proc that generates DOT and writes to disk.
  ##
  ## **Parameters:**
  ## - `graph`: The typestate graph to visualize
  ## - `filename`: Output file path (e.g., "file_typestate.dot")
  ##
  ## **Example:**
  ## ```nim
  ## writeDotFile(myGraph, "output/file_typestate.dot")
  ## ```
  writeFile(filename, generateDot(graph))
