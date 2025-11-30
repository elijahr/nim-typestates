## Core type definitions for the typestate system.
##
## This module defines the internal representation of typestates, states,
## and transitions used during compile-time validation.
##
## These types are primarily used internally by the `typestate` macro and
## `{.transition.}` pragma. Most users won't interact with them directly.

import std/[macros, tables]

type
  State* = object
    ## Represents a single state in a typestate machine.
    ##
    ## Each state corresponds to a distinct type that the user defines.
    ## For example, in a file typestate, `Closed` and `Open` would each
    ## be represented by a `State` object.
    ##
    ## **Fields:**
    ## - `name`: The string name of the state (e.g., "Closed", "Open")
    ## - `typeName`: The AST node representing the type identifier
    name*: string
    typeName*: NimNode

  Transition* = object
    ## Represents a valid state transition in the typestate graph.
    ##
    ## Transitions define which state changes are allowed. They can be:
    ## - **Simple**: `Closed -> Open` (one source, one destination)
    ## - **Branching**: `Closed -> Open | Errored` (one source, multiple destinations)
    ## - **Wildcard**: `* -> Closed` (any state can transition to Closed)
    ##
    ## **Fields:**
    ## - `fromState`: Source state name, or "*" for wildcard
    ## - `toStates`: List of valid destination states
    ## - `isWildcard`: True if this is a wildcard transition (`* -> X`)
    ## - `declaredAt`: Source location for error messages
    ##
    ## **Example:**
    ## ```nim
    ## # This DSL:
    ## # Closed -> Open | Errored
    ## # Becomes:
    ## Transition(
    ##   fromState: "Closed",
    ##   toStates: @["Open", "Errored"],
    ##   isWildcard: false
    ## )
    ## ```
    fromState*: string
    toStates*: seq[string]
    isWildcard*: bool
    declaredAt*: LineInfo

  TypestateGraph* = object
    ## The complete graph of states and transitions for a typestate.
    ##
    ## This is the central data structure that holds all information about
    ## a typestate declaration. It is built by the parser from the DSL syntax
    ## and stored in the compile-time registry for later validation.
    ##
    ## **Fields:**
    ## - `name`: The base type name (e.g., "File" in `typestate File:`)
    ## - `states`: Map of state names to State objects
    ## - `transitions`: List of all declared transitions
    ## - `isSealed`: If true, no extensions allowed from other modules
    ## - `strictTransitions`: If true, all procs on states must be categorized
    ## - `declaredAt`: Source location of the typestate declaration
    ##
    ## **Example:**
    ## ```nim
    ## typestate File:
    ##   states Closed, Open
    ##   transitions:
    ##     Closed -> Open
    ##     Open -> Closed
    ## ```
    ## Creates a TypestateGraph with name="File", two states, and two transitions.
    name*: string
    states*: Table[string, State]
    transitions*: seq[Transition]
    isSealed*: bool = true
    strictTransitions*: bool = true
    declaredAt*: LineInfo
    declaredInModule*: string  ## Module filename where typestate was declared

proc hasTransition*(graph: TypestateGraph, fromState, toState: string): bool =
  ## Check if a transition from `fromState` to `toState` is valid.
  ##
  ## This proc checks both explicit transitions and wildcard transitions.
  ## A transition is valid if:
  ## - There's an explicit transition `fromState -> toState`, OR
  ## - There's a wildcard transition `* -> toState`
  ##
  ## **Parameters:**
  ## - `graph`: The typestate graph to check
  ## - `fromState`: The source state name
  ## - `toState`: The destination state name
  ##
  ## **Returns:** `true` if the transition is allowed, `false` otherwise
  ##
  ## **Example:**
  ## ```nim
  ## # Given: Closed -> Open, * -> Closed
  ## graph.hasTransition("Closed", "Open")   # true
  ## graph.hasTransition("Open", "Closed")   # true (via wildcard)
  ## graph.hasTransition("Closed", "Closed") # true (via wildcard)
  ## graph.hasTransition("Open", "Open")     # false (not declared)
  ## ```
  for t in graph.transitions:
    if t.isWildcard or t.fromState == fromState:
      if toState in t.toStates:
        return true
  return false

proc validDestinations*(graph: TypestateGraph, fromState: string): seq[string] =
  ## Get all valid destination states from a given state.
  ##
  ## This includes both explicit transitions from `fromState` and
  ## destinations reachable via wildcard transitions.
  ##
  ## **Parameters:**
  ## - `graph`: The typestate graph to query
  ## - `fromState`: The source state to check transitions from
  ##
  ## **Returns:** A sequence of state names that can be transitioned to
  ##
  ## **Example:**
  ## ```nim
  ## # Given: Closed -> Open | Errored, * -> Closed
  ## graph.validDestinations("Closed")  # @["Open", "Errored", "Closed"]
  ## graph.validDestinations("Open")    # @["Closed"]
  ## ```
  result = @[]
  for t in graph.transitions:
    if t.isWildcard or t.fromState == fromState:
      for dest in t.toStates:
        if dest notin result:
          result.add dest
