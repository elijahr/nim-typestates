## Test self-transitions (A -> A)

import ../src/typestates

type
  Connection = object
    retries: int
  Connected = distinct Connection
  Disconnected = distinct Connection

typestate Connection:
  strictTransitions = false  # For simpler testing
  isSealed = false
  states Connected, Disconnected
  transitions:
    Disconnected -> Connected
    Connected -> Connected      # Self-transition: reconnect/refresh
    Connected -> Disconnected

proc connect(c: Disconnected): Connected {.transition.} =
  result = Connected(c.Connection)

proc reconnect(c: Connected): Connected {.transition.} =
  ## Self-transition: refresh the connection
  var conn = c.Connection
  conn.retries += 1
  result = Connected(conn)

proc disconnect(c: Connected): Disconnected {.transition.} =
  result = Disconnected(c.Connection)

# Test self-transition
var conn = Disconnected(Connection(retries: 0))
var connected = conn.connect()
connected = connected.reconnect()  # Self-transition
connected = connected.reconnect()  # Again
doAssert connected.Connection.retries == 2
let disconnected = connected.disconnect()

echo "self-transition test passed"
