## Test: Transitioning FROM a terminal state should fail
## Expected error: "Cannot transition FROM terminal state"
import ../../../src/typestates

type
  Connection = object
  Disconnected = distinct Connection
  Connected = distinct Connection
  Closed = distinct Connection

typestate Connection:
  consumeOnTransition = false
  states Disconnected, Connected, Closed
  initial:
    Disconnected
  terminal:
    Closed
  transitions:
    Disconnected -> Connected
    Connected -> Closed
    Closed -> Disconnected # ERROR: Cannot transition FROM terminal state

# This should fail during typestate validation
proc reopen(c: Closed): Disconnected {.transition.} =
  Disconnected(Connection())
