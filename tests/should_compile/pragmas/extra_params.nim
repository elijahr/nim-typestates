## Test: Transition proc with extra parameters
import ../../../src/typestates

type
  Database = object
    host: string
    port: int
    connected: bool
  Disconnected = distinct Database
  Connected = distinct Database

typestate Database:
  isSealed = false
  strictTransitions = false
  states Disconnected, Connected
  transitions:
    Disconnected -> Connected
    Connected -> Disconnected

proc connect(db: Disconnected, host: string, port: int): Connected {.transition.} =
  var d = db.Database
  d.host = host
  d.port = port
  d.connected = true
  Connected(d)

proc disconnect(db: Connected): Disconnected {.transition.} =
  var d = db.Database
  d.connected = false
  Disconnected(d)

let db = Disconnected(Database())
let connected = db.connect("localhost", 5432)
doAssert connected.Database.host == "localhost"
doAssert connected.Database.port == 5432
echo "extra_params test passed"
