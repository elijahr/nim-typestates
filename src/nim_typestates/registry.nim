import std/[tables, macros, options]
import types

export tables  # Needed for `in` operator on Table

# Compile-time registry of all typestates
var typestateRegistry* {.compileTime.}: Table[string, TypestateGraph]

template registerTypestate*(graph: TypestateGraph) =
  ## Register a typestate graph in the compile-time registry
  if graph.name in typestateRegistry:
    # Extension: merge with existing
    var existing = typestateRegistry[graph.name]
    for name, state in graph.states:
      existing.states[name] = state
    for trans in graph.transitions:
      existing.transitions.add trans
    typestateRegistry[graph.name] = existing
  else:
    typestateRegistry[graph.name] = graph

template hasTypestate*(name: string): bool =
  name in typestateRegistry

template getTypestate*(name: string): TypestateGraph =
  block:
    if name notin typestateRegistry:
      error("Unknown typestate: " & name)
    typestateRegistry[name]

proc findTypestateForState*(stateName: string): Option[TypestateGraph] {.compileTime.} =
  ## Find which typestate a given state belongs to
  for name, graph in typestateRegistry:
    if stateName in graph.states:
      return some(graph)
  return none(TypestateGraph)
