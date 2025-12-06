## Test valid initial/terminal state usage.

import ../src/typestates

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

proc connect(d: Disconnected): Connected {.transition.} =
  Connected(Connection())

proc close(c: Connected): Closed {.transition.} =
  Closed(Connection())

# Test it works
let d = Disconnected(Connection())
let c = d.connect()
let closed = c.close()
echo "Initial/terminal states work correctly!"
