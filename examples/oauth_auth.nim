## OAuth 2.0 Authentication Flow with Typestates
##
## OAuth flows are notoriously easy to get wrong:
## - Using an expired token
## - Calling API before authenticating
## - Refreshing with an invalid refresh token
## - Skipping PKCE verification
##
## This example models the Authorization Code + PKCE flow.

import ../src/nim_typestates
import std/strutils

type
  OAuthSession = object
    clientId: string
    redirectUri: string
    codeVerifier: string     # PKCE
    codeChallenge: string    # PKCE
    authCode: string
    accessToken: string
    refreshToken: string
    expiresAt: int64

  # OAuth states
  Unauthenticated = distinct OAuthSession  ## No tokens yet
  AwaitingCallback = distinct OAuthSession ## Auth URL generated, waiting for callback
  Authenticated = distinct OAuthSession    ## Have valid access token
  TokenExpired = distinct OAuthSession     ## Access token expired, need refresh
  RefreshFailed = distinct OAuthSession    ## Refresh failed, need re-auth

typestate OAuthSession:
  states Unauthenticated, AwaitingCallback, Authenticated, TokenExpired, RefreshFailed
  transitions:
    Unauthenticated -> AwaitingCallback    # Start auth flow
    AwaitingCallback -> Authenticated      # Callback received, tokens exchanged
    Authenticated -> TokenExpired          # Token expired
    TokenExpired -> Authenticated          # Refresh succeeded
    TokenExpired -> RefreshFailed          # Refresh failed
    RefreshFailed -> AwaitingCallback      # Start over
    * -> Unauthenticated                   # Logout

# ============================================================================
# Starting the flow
# ============================================================================

proc startAuth(session: Unauthenticated, clientId: string, redirectUri: string): AwaitingCallback {.transition.} =
  ## Generate authorization URL and PKCE challenge.
  var s = session.OAuthSession
  s.clientId = clientId
  s.redirectUri = redirectUri
  s.codeVerifier = "random_verifier_string_43_chars_min"  # In prod: secure random
  s.codeChallenge = "hashed_challenge"  # In prod: SHA256(verifier)

  let authUrl = "https://auth.example.com/authorize?" &
    "client_id=" & clientId &
    "&redirect_uri=" & redirectUri &
    "&code_challenge=" & s.codeChallenge &
    "&code_challenge_method=S256"

  echo "  [OAUTH] Authorization URL generated"
  echo "  [OAUTH] Redirect user to: ", authUrl[0..50], "..."
  result = AwaitingCallback(s)

# ============================================================================
# Handling the callback
# ============================================================================

proc handleCallback(session: AwaitingCallback, authCode: string): Authenticated {.transition.} =
  ## Exchange authorization code for tokens.
  var s = session.OAuthSession
  s.authCode = authCode

  # In production: POST to token endpoint with code + code_verifier
  echo "  [OAUTH] Exchanging auth code for tokens..."
  echo "  [OAUTH] Verifying PKCE: code_verifier=", s.codeVerifier[0..10], "..."

  s.accessToken = "eyJhbGc..." & authCode[0..5]
  s.refreshToken = "refresh_" & authCode[0..5]
  s.expiresAt = 1234567890 + 3600

  echo "  [OAUTH] Access token received (expires in 1h)"
  result = Authenticated(s)

# ============================================================================
# Using the API
# ============================================================================

proc callApi(session: Authenticated, endpoint: string): string {.notATransition.} =
  ## Make an authenticated API call.
  echo "  [API] GET ", endpoint
  echo "  [API] Authorization: Bearer ", session.OAuthSession.accessToken[0..10], "..."
  result = """{"user": "alice", "email": "alice@example.com"}"""

proc getAccessToken(session: Authenticated): string =
  ## Get the current access token for manual use.
  session.OAuthSession.accessToken

# ============================================================================
# Token expiration and refresh
# ============================================================================

proc tokenExpired(session: Authenticated): TokenExpired {.transition.} =
  ## Mark the access token as expired.
  echo "  [OAUTH] Access token expired!"
  result = TokenExpired(session.OAuthSession)

proc refresh(session: TokenExpired): Authenticated {.transition.} =
  ## Refresh the access token using the refresh token.
  var s = session.OAuthSession

  # In production: POST to token endpoint with refresh_token
  echo "  [OAUTH] Refreshing token using: ", s.refreshToken[0..10], "..."

  s.accessToken = "eyJhbGc...refreshed"
  s.expiresAt = 1234567890 + 7200

  echo "  [OAUTH] New access token received"
  result = Authenticated(s)

proc refreshFailed(session: TokenExpired): RefreshFailed {.transition.} =
  ## Handle refresh failure (e.g., refresh token revoked).
  echo "  [OAUTH] Refresh failed! Token may be revoked."
  result = RefreshFailed(session.OAuthSession)

proc restartAuth(session: RefreshFailed): AwaitingCallback {.transition.} =
  ## Start authentication flow again after refresh failure.
  var s = session.OAuthSession
  s.accessToken = ""
  s.refreshToken = ""
  s.codeVerifier = "new_verifier_for_retry"
  s.codeChallenge = "new_challenge"

  echo "  [OAUTH] Starting fresh authentication..."
  result = AwaitingCallback(s)

# ============================================================================
# Logout
# ============================================================================

proc logout(session: Authenticated): Unauthenticated {.transition.} =
  ## Log out and revoke tokens.
  echo "  [OAUTH] Logging out, revoking tokens..."
  result = Unauthenticated(OAuthSession())

# ============================================================================
# Example Usage
# ============================================================================

when isMainModule:
  echo "=== OAuth 2.0 Authentication Demo ===\n"

  echo "1. Creating unauthenticated session..."
  let session = Unauthenticated(OAuthSession())

  echo "\n2. Starting OAuth flow (PKCE)..."
  let awaiting = session.startAuth(
    clientId = "my-app-client-id",
    redirectUri = "myapp://callback"
  )

  echo "\n3. User authorizes, handling callback..."
  let authed = awaiting.handleCallback(authCode = "abc123xyz")

  echo "\n4. Making authenticated API calls..."
  let userData = authed.callApi("/api/user/me")
  echo "   Response: ", userData

  echo "\n5. Simulating token expiration..."
  let expired = authed.tokenExpired()

  echo "\n6. Refreshing access token..."
  let refreshed = expired.refresh()

  echo "\n7. Making another API call with new token..."
  let moreData = refreshed.callApi("/api/user/settings")

  echo "\n8. Logging out..."
  let loggedOut = refreshed.logout()

  echo "\n=== OAuth flow complete! ===\n"

  # =========================================================================
  # COMPILE-TIME ERRORS - These bugs are prevented:
  # =========================================================================

  echo "The following bugs are caught at COMPILE TIME:\n"

  # BUG 1: API call without authentication
  # let bad1 = session.callApi("/api/secret")
  echo "  [PREVENTED] callApi() on Unauthenticated session"

  # BUG 2: API call with expired token
  # let bad2 = expired.callApi("/api/data")
  echo "  [PREVENTED] callApi() on TokenExpired session"

  # BUG 3: Refresh without expiration
  # let bad3 = authed.refresh()
  echo "  [PREVENTED] refresh() on Authenticated session (not expired)"

  # BUG 4: Handle callback twice
  # let bad4 = authed.handleCallback("another_code")
  echo "  [PREVENTED] handleCallback() on Authenticated session"

  # BUG 5: Use logged out session
  # let bad5 = loggedOut.getAccessToken()
  echo "  [PREVENTED] getAccessToken() on Unauthenticated session"

  echo "\nUncomment any of the 'bad' lines above to see the compile error!"
