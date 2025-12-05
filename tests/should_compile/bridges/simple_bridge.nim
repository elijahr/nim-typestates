## Test: Simple bridge between typestates
import ../../../src/typestates

type
  Auth = object
    userId: string
  Pending = distinct Auth
  Authenticated = distinct Auth

  Session = object
    userId: string
  Active = distinct Session

typestate Session:
  isSealed = false
  strictTransitions = false
  states Active

typestate Auth:
  isSealed = false
  strictTransitions = false
  states Pending, Authenticated
  transitions:
    Pending -> Authenticated
  bridges:
    Authenticated -> Session.Active

proc login(a: Pending): Authenticated {.transition.} =
  var auth = a.Auth
  auth.userId = "user123"
  Authenticated(auth)

proc createSession(a: Authenticated): Active {.transition.} =
  Active(Session(userId: a.Auth.userId))

let pending = Pending(Auth(userId: ""))
let authed = pending.login()
let session = authed.createSession()
doAssert session.Session.userId == "user123"
echo "simple_bridge test passed"
