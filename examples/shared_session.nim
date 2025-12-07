## Shared Session with ref Types
##
## When multiple parts of your code need access to the same stateful object,
## use `ref` types. This is common for:
## - Session objects shared across handlers
## - Connection pools
## - Shared resources in async code
##
## This example shows how typestates work with heap-allocated ref types.
##
## Run: nim c -r examples/shared_session.nim

import ../src/typestates

type
  Session = object
    id: string
    userId: int
    data: string

  # Session states
  Unauthenticated = distinct Session
  Authenticated = distinct Session
  Expired = distinct Session

typestate Session:
  # Shared sessions need to be read from multiple places
  consumeOnTransition = false
  states Unauthenticated, Authenticated, Expired
  transitions:
    Unauthenticated -> Authenticated
    Authenticated -> Expired

# ============================================================================
# Session Operations (ref types)
# ============================================================================

proc newSession(id: string): ref Unauthenticated =
  ## Create a new heap-allocated session.
  result = new(Unauthenticated)
  result[] = Unauthenticated(Session(id: id))
  echo "  [SESSION] Created: ", id

proc authenticate(session: ref Unauthenticated, userId: int): ref Authenticated {.transition.} =
  ## Authenticate the session - works with ref types.
  var s = Session(session[])
  s.userId = userId
  result = new(Authenticated)
  result[] = Authenticated(s)
  echo "  [SESSION] Authenticated user ", userId

proc expire(session: ref Authenticated): ref Expired {.transition.} =
  ## Expire the session.
  result = new(Expired)
  result[] = Expired(Session(session[]))
  echo "  [SESSION] Expired"

proc setData(session: ref Authenticated, data: string) =
  ## Modify session data (only when authenticated).
  var s = Session(session[])
  s.data = data
  session[] = Authenticated(s)
  echo "  [SESSION] Data set: ", data

proc getData(session: ref Authenticated): string =
  ## Read session data.
  Session(session[]).data

proc getUserId(session: ref Authenticated): int =
  ## Get the authenticated user ID.
  Session(session[]).userId

# ============================================================================
# Example: Multiple references to same session
# ============================================================================

when isMainModule:
  echo "=== Shared Session Demo (ref types) ===\n"

  echo "1. Creating session..."
  let session = newSession("sess-abc123")

  echo "\n2. Authenticating..."
  let authSession = session.authenticate(42)

  echo "\n3. Multiple parts of code can access the same session..."
  # Simulate different parts of the application using the session
  authSession.setData("user preferences")
  echo "   Handler A reads: ", authSession.getData()
  echo "   Handler B reads user: ", authSession.getUserId()

  echo "\n4. Expiring session..."
  let expiredSession = authSession.expire()

  echo "\n=== Session lifecycle complete! ===\n"

  # =========================================================================
  # COMPILE-TIME ERRORS
  # =========================================================================

  echo "The following bugs are caught at COMPILE TIME:\n"

  # BUG 1: Setting data on unauthenticated session
  # session.setData("hack")  # ERROR: no matching proc for ref Unauthenticated
  echo "  [PREVENTED] setData() on unauthenticated session"

  # BUG 2: Getting user ID from expired session
  # echo expiredSession.getUserId()  # ERROR: no matching proc for ref Expired
  echo "  [PREVENTED] getUserId() on expired session"

  # BUG 3: Authenticating already-authenticated session
  # discard authSession.authenticate(99)  # ERROR: no matching proc
  echo "  [PREVENTED] authenticate() on already-authenticated session"

  echo "\nRef types work seamlessly with typestates!"
