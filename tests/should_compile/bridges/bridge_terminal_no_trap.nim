## Test: a state that bridges OUT of the typestate is a legitimate exit
## under liveness analysis. With `terminal: Failed` declared, Authenticated
## (which has no in-typestate transition out, only a bridge to Session.Active)
## must NOT be flagged as a trap state.
import ../../../src/typestates

type
  Auth = object
    userId: string

  Pending = distinct Auth
  Authenticated = distinct Auth
  Failed = distinct Auth

  Session = object
    userId: string

  Active = distinct Session

typestate Session:
  consumeOnTransition = false
  strictTransitions = false
  states Active

typestate Auth:
  consumeOnTransition = false
  strictTransitions = false
  states Pending, Authenticated, Failed
  initial:
    Pending
  terminal:
    Failed
  transitions:
    Pending -> Authenticated
    Pending -> Failed
  bridges:
    Authenticated -> Session.Active

proc login(a: Pending): Authenticated {.transition.} =
  Authenticated(Auth(userId: "user"))

proc fail(a: Pending): Failed {.transition.} =
  Failed(a.Auth)

proc createSession(a: Authenticated): Active {.transition.} =
  Active(Session(userId: a.Auth.userId))

let p = Pending(Auth(userId: ""))
let authed = p.login()
let s = authed.createSession()
doAssert s.Session.userId == "user"
echo "bridge_terminal_no_trap test passed"
