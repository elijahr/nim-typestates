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
  states Pending, Authenticated, Failed
  transitions:
    Pending -> Authenticated | Failed
  bridges:
    # Bridge to typestate defined in another module
    Authenticated -> Session.Active
    Failed -> Session.Guest

# Transition within AuthFlow (branching: Pending -> Authenticated | Failed)
proc authenticate*(a: Pending): PendingBranch {.transition.} =
  if a.AuthFlow.token.len > 0:
    toPendingBranch(Authenticated(a.AuthFlow))
  else:
    toPendingBranch(Failed(a.AuthFlow))

# Bridge transition: AuthFlow -> Session
proc startSession*(a: Authenticated, timeout: int): Active {.transition.} =
  newActiveSession(a.AuthFlow.userId, timeout)

# Bridge transition: Failed AuthFlow -> Guest Session
proc fallbackToGuest*(a: Failed): Guest {.transition.} =
  newGuestSession()
