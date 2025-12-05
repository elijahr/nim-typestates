## Core type definitions for the typestate system.
##
## This module defines the internal representation of typestates, states,
## and transitions used during compile-time validation.
##
## These types are primarily used internally by the `typestate` macro and
## `{.transition.}` pragma. Most users won't interact with them directly.

import std/[macros, tables, strutils]

proc extractBaseName*(stateRepr: string): string =
  ## Extract the base type name from a state repr string.
  ##
  ## Used for comparing state names when generic parameters may differ:
  ##
  ## - `"Empty"` -> `"Empty"`
  ## - `"Empty[T]"` -> `"Empty"`
  ## - `"Container[K, V]"` -> `"Container"`
  ## - `"ref Closed"` -> `"Closed"`
  ##
  ## :param stateRepr: Full state repr string
  ## :returns: Base name without generic parameters
  result = stateRepr
  # Strip ref/ptr prefix
  if result.startsWith("ref "):
    result = result[4..^1]
  elif result.startsWith("ptr "):
    result = result[4..^1]
  # Strip generic parameters
  let bracketPos = result.find('[')
  if bracketPos >= 0:
    result = result[0..<bracketPos]
  # Strip module qualification
  let dotPos = result.rfind('.')
  if dotPos >= 0:
    result = result[dotPos+1..^1]
  result = result.strip()

type
  State* = object
    ## Represents a single state in a typestate machine.
    ##
    ## Each state corresponds to a distinct type that the user defines.
    ## States can be simple identifiers or generic types.
    ##
    ## Examples:
    ##
    ## - Simple: `name="Closed"`, `fullRepr="Closed"`
    ## - Generic: `name="Container"`, `fullRepr="Container[T]"`
    ## - Ref type: `name="Closed"`, `fullRepr="ref Closed"`
    ##
    ## :var name: Base name for lookup (e.g., "Closed", "Container")
    ## :var fullRepr: Full type representation (e.g., "Closed", "Container[T]")
    ## :var typeName: The raw AST node for code generation
    name*: string
    fullRepr*: string
    typeName*: NimNode

  Transition* = object
    ## Represents a valid state transition in the typestate graph.
    ##
    ## Transitions define which state changes are allowed. They can be:
    ##
    ## - **Simple**: `Closed -> Open` (one source, one destination)
    ## - **Branching**: `Closed -> Open | Errored` (one source, multiple destinations)
    ## - **Wildcard**: `* -> Closed` (any state can transition to Closed)
    ##
    ## Example:
    ##
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
    ##
    ## :var fromState: Source state name, or "*" for wildcard
    ## :var toStates: List of valid destination states
    ## :var isWildcard: True if this is a wildcard transition (`* -> X`)
    ## :var declaredAt: Source location for error messages
    fromState*: string
    toStates*: seq[string]
    isWildcard*: bool
    declaredAt*: LineInfo

  Bridge* = object
    ## Represents a cross-typestate bridge declaration.
    ##
    ## Bridges allow terminal states of one typestate to transition into
    ## states of a completely different typestate. They enable modeling
    ## resource transformation, wrapping, and protocol handoff.
    ##
    ## Example:
    ##
    ## ```nim
    ## # In AuthFlow typestate:
    ## # bridges:
    ## #   Authenticated -> Session.Active
    ## # Becomes:
    ## Bridge(
    ##   fromState: "Authenticated",
    ##   toTypestate: "Session",
    ##   toState: "Active"
    ## )
    ## ```
    ##
    ## :var fromState: Source state name in this typestate
    ## :var toTypestate: Name of the destination typestate
    ## :var toState: State name in the destination typestate
    ## :var declaredAt: Source location for error messages
    fromState*: string
    toTypestate*: string
    toState*: string
    declaredAt*: LineInfo

  TypestateGraph* = object
    ## The complete graph of states and transitions for a typestate.
    ##
    ## This is the central data structure that holds all information about
    ## a typestate declaration. It is built by the parser from the DSL syntax
    ## and stored in the compile-time registry for later validation.
    ##
    ## Example:
    ##
    ## ```nim
    ## typestate File:
    ##   states Closed, Open
    ##   transitions:
    ##     Closed -> Open
    ##     Open -> Closed
    ## ```
    ##
    ## Creates a TypestateGraph with name="File", two states, and two transitions.
    ##
    ## :var name: The base type name (e.g., "File" in `typestate File:`)
    ## :var states: Map of state names to State objects
    ## :var transitions: List of all declared transitions
    ## :var strictTransitions: If true, all procs on states must be categorized
    ## :var declaredAt: Source location of the typestate declaration
    ## :var declaredInModule: Module filename where typestate was declared
    name*: string
    states*: Table[string, State]
    transitions*: seq[Transition]
    bridges*: seq[Bridge]
    strictTransitions*: bool = true
    declaredAt*: LineInfo
    declaredInModule*: string

proc `==`*(a, b: Transition): bool =
  ## Compare two transitions for equality.
  ##
  ## Two transitions are equal if they have the same source state,
  ## destination states, and wildcard status. The declaration location
  ## is not considered for equality.
  ##
  ## :param a: First transition to compare
  ## :param b: Second transition to compare
  ## :returns: `true` if transitions are semantically equivalent
  a.fromState == b.fromState and
    a.toStates == b.toStates and
    a.isWildcard == b.isWildcard

proc `==`*(a, b: Bridge): bool =
  ## Compare two bridges for equality.
  ##
  ## Two bridges are equal if they have the same source state,
  ## destination typestate, and destination state. The declaration
  ## location is not considered for equality.
  ##
  ## :param a: First bridge to compare
  ## :param b: Second bridge to compare
  ## :returns: `true` if bridges are semantically equivalent
  a.fromState == b.fromState and
    a.toTypestate == b.toTypestate and
    a.toState == b.toState

proc hasTransition*(graph: TypestateGraph, fromState, toState: string): bool =
  ## Check if a transition from `fromState` to `toState` is valid.
  ##
  ## This proc checks both explicit transitions and wildcard transitions.
  ## A transition is valid if there's an explicit transition
  ## `fromState -> toState`, or there's a wildcard transition `* -> toState`.
  ##
  ## Comparisons use base names to support generic types:
  ## - `hasTransition(g, "Empty", "Full")` matches `Empty[T] -> Full[T]`
  ##
  ## Example:
  ##
  ## ```nim
  ## # Given: Closed -> Open, * -> Closed
  ## graph.hasTransition("Closed", "Open")   # true
  ## graph.hasTransition("Open", "Closed")   # true (via wildcard)
  ## graph.hasTransition("Closed", "Closed") # true (via wildcard)
  ## graph.hasTransition("Open", "Open")     # false (not declared)
  ## ```
  ##
  ## :param graph: The typestate graph to check
  ## :param fromState: The source state name (base name or full repr)
  ## :param toState: The destination state name (base name or full repr)
  ## :returns: `true` if the transition is allowed, `false` otherwise
  let fromBase = extractBaseName(fromState)
  let toBase = extractBaseName(toState)
  for t in graph.transitions:
    let tFromBase = extractBaseName(t.fromState)
    if t.isWildcard or tFromBase == fromBase:
      for dest in t.toStates:
        if extractBaseName(dest) == toBase:
          return true
  return false

proc validDestinations*(graph: TypestateGraph, fromState: string): seq[string] =
  ## Get all valid destination states from a given state.
  ##
  ## This includes both explicit transitions from `fromState` and
  ## destinations reachable via wildcard transitions.
  ##
  ## Comparisons use base names to support generic types.
  ## Returns base names for clearer error messages.
  ##
  ## Example:
  ##
  ## ```nim
  ## # Given: Closed -> Open | Errored, * -> Closed
  ## graph.validDestinations("Closed")  # @["Open", "Errored", "Closed"]
  ## graph.validDestinations("Open")    # @["Closed"]
  ## ```
  ##
  ## :param graph: The typestate graph to query
  ## :param fromState: The source state to check transitions from
  ## :returns: A sequence of state base names that can be transitioned to
  result = @[]
  let fromBase = extractBaseName(fromState)
  for t in graph.transitions:
    let tFromBase = extractBaseName(t.fromState)
    if t.isWildcard or tFromBase == fromBase:
      for dest in t.toStates:
        let destBase = extractBaseName(dest)
        if destBase notin result:
          result.add destBase

proc hasBridge*(graph: TypestateGraph, fromState, toTypestate, toState: string): bool =
  ## Check if a bridge from `fromState` to `toTypestate.toState` is declared.
  ##
  ## Comparisons use base names to support generic types.
  ##
  ## Example:
  ##
  ## ```nim
  ## # Given: Authenticated -> Session.Active
  ## graph.hasBridge("Authenticated", "Session", "Active")  # true
  ## graph.hasBridge("Failed", "Session", "Active")         # false
  ## ```
  ##
  ## :param graph: The typestate graph to check
  ## :param fromState: The source state name
  ## :param toTypestate: The destination typestate name
  ## :param toState: The destination state name
  ## :returns: `true` if the bridge is declared, `false` otherwise
  let fromBase = extractBaseName(fromState)
  let toTypestateBase = extractBaseName(toTypestate)
  let toStateBase = extractBaseName(toState)
  for b in graph.bridges:
    if b.fromState == "*" or extractBaseName(b.fromState) == fromBase:
      if extractBaseName(b.toTypestate) == toTypestateBase and
         extractBaseName(b.toState) == toStateBase:
        return true
  return false

proc validBridges*(graph: TypestateGraph, fromState: string): seq[string] =
  ## Get all valid bridge destinations from a given state.
  ##
  ## Returns dotted notation strings like "Session.Active".
  ##
  ## Example:
  ##
  ## ```nim
  ## # Given: Authenticated -> Session.Active, Failed -> ErrorLog.Entry
  ## graph.validBridges("Authenticated")  # @["Session.Active"]
  ## graph.validBridges("Failed")         # @["ErrorLog.Entry"]
  ## ```
  ##
  ## :param graph: The typestate graph to query
  ## :param fromState: The source state to check bridges from
  ## :returns: A sequence of dotted destination names
  result = @[]
  let fromBase = extractBaseName(fromState)
  for b in graph.bridges:
    if b.fromState == "*" or extractBaseName(b.fromState) == fromBase:
      let dest = b.toTypestate & "." & b.toState
      if dest notin result:
        result.add dest
