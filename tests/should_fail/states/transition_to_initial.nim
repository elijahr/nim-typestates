## Test: Transitioning TO an initial state should fail
## Expected error: "Cannot transition TO initial state"
import ../../../src/typestates

type
  Connection = object
  Disconnected = distinct Connection
  Connected = distinct Connection
  Closed = distinct Connection

typestate Connection:
  consumeOnTransition = false
  states Disconnected, Connected, Closed
  initial: Disconnected
  terminal: Closed
  transitions:
    Disconnected -> Connected
    Connected -> Closed
    Connected -> Disconnected  # ERROR: Cannot transition TO initial state

# This should fail during typestate validation
proc reconnect(c: Connected): Disconnected {.transition.} =
  Disconnected(Connection())
