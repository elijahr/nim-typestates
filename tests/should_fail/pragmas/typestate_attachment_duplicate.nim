## Test (TA-004): a type is attached to two different typestates.
##
## A type may attach to at most one typestate. Declaring two
## `typestate`s and then trying to attach the same type to both must
## surface TA-004 at the second attachment site. The message must name
## the type and the prior (already-attached) typestate.
# expects: "already attached to typestate"
# expects: "TypestateA"
import ../../../src/typestates

type
  StateA1 = object
  StateA2 = object
  StateB1 = object
  StateB2 = object

typestate TypestateA:
  consumeOnTransition = false
  strictTransitions = false
  states StateA1, StateA2
  initial:
    StateA1
  terminal:
    StateA2
  transitions:
    StateA1 -> StateA2

typestate TypestateB:
  consumeOnTransition = false
  strictTransitions = false
  states StateB1, StateB2
  initial:
    StateB1
  terminal:
    StateB2
  transitions:
    StateB1 -> StateB2

# Two attachment pragmas on the same type — second must trigger TA-004.
type Multi {.TypestateA: StateA1, TypestateB: StateB1.} = object
  data: int
