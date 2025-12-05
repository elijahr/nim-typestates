## Compile-time state machine verification for Nim.
##
## This library enforces state machine protocols at compile time through
## Nim's type system. Programs that compile have been verified to contain
## no invalid state transitions.
##
## This approach is known as *correctness by construction*: invalid states
## become unrepresentable rather than checked at runtime.
##
## **Exports:**
##
## - `typestate` macro - Declare states and transitions
## - `{.transition.}` pragma - Mark and validate transition procs
## - `{.notATransition.}` pragma - Mark non-transition procs

import std/macros
import typestates/[types, parser, registry, pragmas, codegen]

export types, pragmas

macro typestate*(name: untyped, body: untyped): untyped =
  ## Define a typestate with states and valid transitions.
  ##
  ## The typestate block declares:
  ##
  ## - **states**: The distinct types that represent each state
  ## - **transitions**: Which state changes are allowed
  ##
  ## Basic syntax:
  ##
  ## ```nim
  ## typestate File:
  ##   states Closed, Open, Errored
  ##   transitions:
  ##     Closed -> Open | Errored    # Branching
  ##     Open -> Closed
  ##     * -> Closed                 # Wildcard
  ## ```
  ##
  ## What it generates:
  ##
  ## - `FileState` enum with `fsClosed`, `fsOpen`, `fsErrored`
  ## - `FileStates` union type for generic procs
  ## - `state()` procs for runtime inspection
  ##
  ## Transition syntax:
  ##
  ## - `A -> B` - Simple transition
  ## - `A -> B | C` - Branching (can go to B or C)
  ## - `* -> X` - Wildcard (any state can go to X)
  ##
  ## See also: `{.transition.}` pragma for implementing transitions
  ##
  ## :param name: The base type name (must match your type definition)
  ## :param body: The states and transitions declarations
  ## :returns: Generated helper types (enum, union, state procs)

  # Parse the typestate body
  let graph = parseTypestateBody(name, body)

  # Register for later validation
  registerTypestate(graph)

  # Register states for external checking
  var stateNames: seq[string] = @[]
  for stateName in graph.states.keys:
    stateNames.add stateName
  registerSealedStates(graph.declaredInModule, stateNames)

  # Generate helper types
  result = generateAll(graph)
