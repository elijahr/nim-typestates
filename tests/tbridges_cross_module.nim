## Test cross-module bridges.
## Verifies that bridges work when source and destination typestates
## are defined in different modules.

import bridges_cross_module/session_typestate
import bridges_cross_module/auth_typestate

# Test the full flow across modules
block test_successful_auth:
  let pending = Pending(AuthFlow(userId: "alice", token: "secret123"))
  let result = authenticate(pending)

  # AuthResult uses "a" prefix (first letter of AuthResult)
  case result.kind
  of aAuthenticated:
    let session = startSession(result.authenticated, 7200)
    doAssert session.Session.userId == "alice"
    doAssert session.Session.expires == 7200
    echo "PASS: Cross-module bridge (Authenticated -> Session.Active) works"
  of aFailed:
    doAssert false, "Expected authentication to succeed"

block test_failed_auth:
  let pending = Pending(AuthFlow(userId: "bob", token: "")) # Empty token = fail
  let result = authenticate(pending)

  case result.kind
  of aAuthenticated:
    doAssert false, "Expected authentication to fail"
  of aFailed:
    let guestSession = fallbackToGuest(result.failed)
    doAssert guestSession.Session.userId == "anonymous"
    echo "PASS: Cross-module bridge (Failed -> Session.Guest) works"

echo "All cross-module bridge tests passed!"
