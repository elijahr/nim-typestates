## Test: Transition proc with no parameters should fail
## Expected error: "must take at least one state parameter"
import ../../../src/typestates

type
  Machine = object
  On = distinct Machine
  Off = distinct Machine

typestate Machine:
  consumeOnTransition = false # Opt out for existing tests
  states On, Off
  transitions:
    Off -> On

# No parameters - invalid
proc magicOn(): On {.transition.} =
  On(Machine())
