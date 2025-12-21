## Source typestate with bridges to Session (defined in another module).
## This tests cross-module bridge functionality.

import ../../src/typestates
import session_typestate

type
  AuthFlow* = object
    userId*: string
    token*: string

  Pending* = distinct AuthFlow
  Authenticated* = distinct AuthFlow
  Failed* = distinct AuthFlow

typestate AuthFlow:
  consumeOnTransition = false # Opt out for this test
  states Pending, Authenticated, Failed
  transitions:
    Pending -> (Authenticated | Failed) as AuthResult
  bridges:
    # Bridge to typestate defined in another module
    Authenticated -> Session.Active
    Failed -> Session.Guest

# Transition within AuthFlow (branching: Pending -> Authenticated | Failed)
proc authenticate*(a: Pending): AuthResult {.transition.} =
  if a.AuthFlow.token.len > 0:
    AuthResult -> Authenticated(a.AuthFlow)
  else:
    AuthResult -> Failed(a.AuthFlow)

# Bridge transition: AuthFlow -> Session
proc startSession*(a: Authenticated, timeout: int): Active {.transition.} =
  newActiveSession(a.AuthFlow.userId, timeout)

# Bridge transition: Failed AuthFlow -> Guest Session
proc fallbackToGuest*(a: Failed): Guest {.transition.} =
  newGuestSession()
