## Test typestate extension when isSealed = false

import ../src/nim_typestates

type
  Connection = object
    host: string
  Disconnected = distinct Connection
  Connected = distinct Connection
  Authenticated = distinct Connection

# First typestate - NOT sealed
typestate Connection:
  isSealed = false
  strictTransitions = false  # For testing
  states Disconnected, Connected
  transitions:
    Disconnected -> Connected
    Connected -> Disconnected

# Extension - add new state and transitions
typestate Connection:
  states Authenticated
  transitions:
    Connected -> Authenticated
    Authenticated -> Disconnected

# Test that all transitions work
proc connect(c: Disconnected): Connected {.transition.} =
  result = Connected(c.Connection)

proc authenticate(c: Connected): Authenticated {.transition.} =
  result = Authenticated(c.Connection)

proc disconnect(c: Authenticated): Disconnected {.transition.} =
  result = Disconnected(c.Connection)

proc disconnectConnected(c: Connected): Disconnected {.transition.} =
  result = Disconnected(c.Connection)

# Usage test
let conn = Disconnected(Connection(host: "localhost"))
let connected = conn.connect()
let authed = connected.authenticate()
let disconnected = authed.disconnect()

echo "extension test passed"
