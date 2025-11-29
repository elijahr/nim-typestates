import std/[strutils, tables]
import types

proc generateDot*(graph: TypestateGraph): string =
  ## Generate a GraphViz DOT representation of the typestate
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
  ## Write the DOT representation to a file
  writeFile(filename, generateDot(graph))
