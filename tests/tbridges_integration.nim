import ../src/typestates

# Define destination typestate first
type
  Session = object
    userId: string
    expires: int
  Active = distinct Session
  Guest = distinct Session
  Expired = distinct Session

typestate Session:
  states Active, Guest, Expired
  transitions:
    Active -> Expired
    Guest -> Expired

# Define source typestate with bridges
type
  AuthFlow = object
    userId: string
    token: string
  Pending = distinct AuthFlow
  Authenticated = distinct AuthFlow
  Failed = distinct AuthFlow

typestate AuthFlow:
  states Pending, Authenticated, Failed
  transitions:
    Pending -> Authenticated
    Pending -> Failed
  bridges:
    Authenticated -> Session.Active
    Failed -> Session.Guest

# Test bridge with proc
proc startSession(a: Authenticated, timeout: int): Active {.transition.} =
  result = Active(Session(
    userId: a.AuthFlow.userId,
    expires: timeout
  ))

# Test authentication success
proc authenticate(a: Pending): Authenticated {.transition.} =
  result = Authenticated(a.AuthFlow)

# Test authentication failure
proc fail(a: Pending): Failed {.transition.} =
  result = Failed(a.AuthFlow)

# Test bridge with converter
converter toGuest(a: Failed): Guest {.transition.} =
  result = Guest(Session(
    userId: "anonymous",
    expires: 3600
  ))

# Test that bridges work end-to-end
block test_bridge_flow:
  let pending = Pending(AuthFlow(userId: "alice", token: ""))
  let authed = authenticate(pending)
  let session = startSession(authed, 7200)
  doAssert session.Session.userId == "alice"
  echo "Bridge from Authenticated to Session.Active works"

block test_converter_bridge:
  let pending = Pending(AuthFlow(userId: "bob", token: ""))
  let failed = fail(pending)
  let guestSession: Guest = failed
  doAssert guestSession.Session.userId == "anonymous"
  echo "Converter bridge from Failed to Session.Guest works"

# Test wildcard bridge
type
  Shutdown = object
  Terminal = distinct Shutdown

typestate Shutdown:
  states Terminal
  transitions:
    Terminal -> Terminal

type
  Request = object
  Processing = distinct Request
  Complete = distinct Request

typestate Request:
  states Processing, Complete
  transitions:
    Processing -> Complete
  bridges:
    * -> Shutdown.Terminal

proc emergency(r: Processing): Terminal {.transition.} =
  result = Terminal(Shutdown())

proc abort(r: Complete): Terminal {.transition.} =
  result = Terminal(Shutdown())

block test_wildcard_bridge:
  let req = Processing(Request())
  let term = emergency(req)
  doAssert term is Terminal
  echo "Wildcard bridge (* -> Shutdown.Terminal) works"

echo "All bridge integration tests passed"
