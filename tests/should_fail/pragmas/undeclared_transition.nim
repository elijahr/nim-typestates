## Test: Undeclared transition should fail
## Expected error: "Undeclared transition"
import ../../../src/typestates

type
  Machine = object
  On = distinct Machine
  Off = distinct Machine
  Broken = distinct Machine  # Not in transitions

typestate Machine:
  consumeOnTransition = false  # Opt out for existing tests
  states On, Off
  transitions:
    Off -> On
    On -> Off

# This transition is not declared
proc breakIt(m: On): Broken {.transition.} =
  Broken(m.Machine)
