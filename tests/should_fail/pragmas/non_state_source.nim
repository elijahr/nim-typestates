## Test: First param not a state type should fail
## Expected error: "not part of any registered typestate"
import ../../../src/typestates

type
  Machine = object
  On = distinct Machine
  Off = distinct Machine
  NotAState = object  # Regular object, not distinct

typestate Machine:
  states On, Off
  transitions:
    Off -> On

# First param is not a registered state
proc badTransition(x: NotAState): On {.transition.} =
  On(Machine())
