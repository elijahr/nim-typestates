## Single-Use Token with Ownership Enforcement
##
## Some resources should only be used once:
## - Password reset tokens
## - One-time payment links
## - Single-use API keys
## - Event tickets
##
## This example uses consumeOnTransition = true (the default) to enforce
## that tokens cannot be copied or reused after consumption.
##
## Run: nim c -r examples/single_use_token.nim

import ../src/typestates

type
  Token = object
    id: string
    value: string
    createdAt: string

  # Token states
  Valid = distinct Token      ## Token is valid, can be used
  Used = distinct Token       ## Token has been consumed
  Expired = distinct Token    ## Token has expired
  Revoked = distinct Token    ## Token was manually revoked

typestate Token:
  # DEFAULT: consumeOnTransition = true
  # This enforces ownership - tokens cannot be copied after creation.
  # Each token can only follow ONE path through the state machine.
  states Valid, Used, Expired, Revoked
  initial: Valid
  terminal: Used
  transitions:
    Valid -> Used       # Consume the token
    Valid -> Expired    # Token expires
    Valid -> Revoked    # Token is revoked

# ============================================================================
# Token Operations
# ============================================================================

proc createToken(id: string, value: string): Valid =
  ## Create a new single-use token.
  echo "  [TOKEN] Created: ", id
  Valid(Token(id: id, value: value, createdAt: "now"))

proc consume(token: sink Valid): Used {.transition.} =
  ## Use the token (one-time only).
  ## sink + consumeOnTransition = true prevents copying, enforcing single-use.
  let t = Token(token)
  echo "  [TOKEN] Consumed: ", t.id
  Used(t)

proc expire(token: Valid): Expired {.transition.} =
  ## Mark token as expired.
  echo "  [TOKEN] Expired: ", Token(token).id
  Expired(Token(token))

proc revoke(token: Valid): Revoked {.transition.} =
  ## Revoke the token.
  echo "  [TOKEN] Revoked: ", Token(token).id
  Revoked(Token(token))

proc getValue(token: Valid): string {.notATransition.} =
  ## Read the token value (only when valid).
  Token(token).value

# ============================================================================
# Example: Password Reset Token
# ============================================================================

when isMainModule:
  echo "=== Single-Use Token Demo ===\n"

  echo "1. Creating and immediately consuming a password reset token..."
  # With consumeOnTransition = true, tokens flow directly through transitions
  let usedToken = createToken("reset-abc123", "secret-reset-value").consume()

  echo "\n=== Token consumed! ===\n"

  # =========================================================================
  # COMPILE-TIME ERRORS - Ownership enforcement prevents these bugs:
  # =========================================================================

  echo "The following bugs are caught at COMPILE TIME:\n"

  # BUG 1: Storing a token and then trying to use it twice
  # let token = createToken("test", "value")
  # let used1 = token.consume()
  # let used2 = token.consume()  # ERROR: token was already moved
  echo "  [PREVENTED] Double consumption of token"

  # BUG 2: Copying token to bypass single-use
  # let token = createToken("test", "value")
  # let backup = token  # ERROR: =copy is not available for Valid
  echo "  [PREVENTED] Copying token to bypass single-use"

  # BUG 3: Reading token value then consuming (uses token twice)
  # let token = createToken("test", "value")
  # echo token.getValue()
  # discard token.consume()  # ERROR: token was not last read in getValue()
  echo "  [PREVENTED] Reading token value prevents later consumption"

  # BUG 4: Using terminal state
  # let reused = usedToken.consume()  # ERROR: Used is a terminal state
  echo "  [PREVENTED] Transitioning from terminal state"

  echo "\nUncomment any of the 'bad' lines above to see the compile error!"
  echo "\n=== Ownership enforcement ensures tokens are truly single-use ==="
