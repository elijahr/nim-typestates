## Compile-time registry for typestate definitions.
##
## This module provides a global compile-time registry that stores all
## declared typestates. The registry enables:
##
## - Looking up typestates by name
## - Finding which typestate a state type belongs to
## - Extending typestates across modules
##
## The registry is used by the `{.transition.}` pragma to validate that
## transitions are allowed.
##
## **Internal module** - most users won't interact with this directly.

import std/[tables, macros, options]
import types

export tables  # Needed for `in` operator on Table

var typestateRegistry* {.compileTime.}: Table[string, TypestateGraph]
  ## Global compile-time storage for all registered typestates.
  ##
  ## Maps typestate names (e.g., "File") to their graph definitions.
  ## This variable is populated by the `typestate` macro and queried
  ## by the `{.transition.}` pragma.

proc validateBridgeDestinations(graph: TypestateGraph) {.compileTime.} =
  ## Validate that all bridge destinations reference existing states.
  ##
  ## For each bridge declared in the graph, checks that:
  ## 1. The destination typestate exists in the registry
  ## 2. The destination state exists in that typestate
  ##
  ## :param graph: The typestate graph to validate
  ## :raises: Compile-time error if any bridge destination is invalid
  for bridge in graph.bridges:
    let destTypestateBase = extractBaseName(bridge.toTypestate)
    if destTypestateBase notin typestateRegistry:
      # Destination typestate not registered yet - this is OK, will be validated
      # when the transition proc is implemented via the {.transition.} pragma
      continue

    let destGraph = typestateRegistry[destTypestateBase]
    let destStateBase = extractBaseName(bridge.toState)

    # Check if the destination state exists in the destination typestate
    var foundState = false
    for stateKey, state in destGraph.states:
      if state.name == destStateBase:
        foundState = true
        break

    if not foundState:
      var validStates: seq[string] = @[]
      for stateKey, state in destGraph.states:
        validStates.add state.name
      error("Bridge destination state '" & bridge.toState &
            "' does not exist in typestate '" & bridge.toTypestate &
            "'. Valid states: " & $validStates)

template registerTypestate*(graph: TypestateGraph) =
  ## Register a typestate graph in the compile-time registry.
  ##
  ## If a typestate with the same name already exists:
  ##
  ## - If sealed: compilation error
  ## - If not sealed: merge states and transitions (extension mode)
  ##
  ## Example:
  ##
  ## ```nim
  ## # First module defines base typestate (with isSealed = false)
  ## typestate File:
  ##   isSealed = false
  ##   states Closed, Open
  ##   transitions:
  ##     Closed -> Open
  ##
  ## # Second module extends it
  ## typestate File:
  ##   states Locked
  ##   transitions:
  ##     Open -> Locked
  ## ```
  ##
  ## :param graph: The typestate graph to register
  if graph.name in typestateRegistry:
    let existing = typestateRegistry[graph.name]
    if existing.isSealed:
      error("Cannot extend sealed typestate '" & graph.name &
            "'. Set isSealed = false or define all states/transitions in one place.")
    # Extension: merge with existing, deduplicating transitions and bridges
    var merged = existing
    for name, state in graph.states:
      merged.states[name] = state
    for trans in graph.transitions:
      if trans notin merged.transitions:
        merged.transitions.add trans
    for bridge in graph.bridges:
      if bridge notin merged.bridges:
        merged.bridges.add bridge
    typestateRegistry[graph.name] = merged
  else:
    typestateRegistry[graph.name] = graph

  # Validate bridge destinations after registration
  validateBridgeDestinations(graph)

template hasTypestate*(name: string): bool =
  ## Check if a typestate with the given name exists in the registry.
  ##
  ## :param name: The typestate name to look up
  ## :returns: `true` if registered, `false` otherwise
  name in typestateRegistry

template getTypestate*(name: string): TypestateGraph =
  ## Retrieve a typestate graph by name.
  ##
  ## :param name: The typestate name to look up
  ## :returns: The `TypestateGraph` for the typestate
  ## :raises: Compile-time error if not found
  block:
    if name notin typestateRegistry:
      error("Unknown typestate: " & name)
    typestateRegistry[name]

proc findTypestateForState*(stateName: string): Option[TypestateGraph] {.compileTime.} =
  ## Find which typestate a given state belongs to.
  ##
  ## Searches all registered typestates to find one containing the
  ## specified state. Used by the `{.transition.}` pragma to determine
  ## which typestate graph to validate against.
  ##
  ## Lookups use base names to support generic types:
  ## - `findTypestateForState("Empty")` finds `typestate Container` with `Empty[T]`
  ##
  ## Example:
  ##
  ## ```nim
  ## # If File typestate has states Closed, Open:
  ## findTypestateForState("Closed")  # some(FileGraph)
  ## findTypestateForState("Unknown") # none
  ##
  ## # If Container typestate has states Empty[T], Full[T]:
  ## findTypestateForState("Empty")   # some(ContainerGraph)
  ## ```
  ##
  ## :param stateName: The state type name (base name, e.g., "Closed", "Empty")
  ## :returns: `some(graph)` if found, `none` if state is not in any typestate
  let searchBase = extractBaseName(stateName)
  for name, graph in typestateRegistry:
    for stateKey, state in graph.states:
      if state.name == searchBase:
        return some(graph)
  return none(TypestateGraph)
