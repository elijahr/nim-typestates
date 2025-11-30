## Compile-time registry for typestate definitions.
##
## This module provides a global compile-time registry that stores all
## declared typestates. The registry enables:
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

template registerTypestate*(graph: TypestateGraph) =
  ## Register a typestate graph in the compile-time registry.
  ##
  ## If a typestate with the same name already exists:
  ## - If sealed: compilation error
  ## - If not sealed: merge states and transitions (extension mode)
  ##
  ## **Parameters:**
  ## - `graph`: The typestate graph to register
  ##
  ## **Example:**
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
  if graph.name in typestateRegistry:
    let existing = typestateRegistry[graph.name]
    if existing.isSealed:
      error("Cannot extend sealed typestate '" & graph.name &
            "'. Set isSealed = false or define all states/transitions in one place.")
    # Extension: merge with existing
    var merged = existing
    for name, state in graph.states:
      merged.states[name] = state
    for trans in graph.transitions:
      merged.transitions.add trans
    typestateRegistry[graph.name] = merged
  else:
    typestateRegistry[graph.name] = graph

template hasTypestate*(name: string): bool =
  ## Check if a typestate with the given name exists in the registry.
  ##
  ## **Parameters:**
  ## - `name`: The typestate name to look up
  ##
  ## **Returns:** `true` if registered, `false` otherwise
  name in typestateRegistry

template getTypestate*(name: string): TypestateGraph =
  ## Retrieve a typestate graph by name.
  ##
  ## **Parameters:**
  ## - `name`: The typestate name to look up
  ##
  ## **Returns:** The `TypestateGraph` for the typestate
  ##
  ## **Raises:** Compile-time error if not found
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
  ## **Parameters:**
  ## - `stateName`: The state type name (e.g., "Closed", "Open")
  ##
  ## **Returns:** `some(graph)` if found, `none` if state is not in any typestate
  ##
  ## **Example:**
  ## ```nim
  ## # If File typestate has states Closed, Open:
  ## findTypestateForState("Closed")  # some(FileGraph)
  ## findTypestateForState("Unknown") # none
  ## ```
  for name, graph in typestateRegistry:
    if stateName in graph.states:
      return some(graph)
  return none(TypestateGraph)
