## Test: Transition with non-empty raises should fail
## Expected error: "non-empty raises list"
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
    On -> Off

proc turnOn(m: Off): On {.transition, raises: [IOError].} =
  On(m.Machine)
