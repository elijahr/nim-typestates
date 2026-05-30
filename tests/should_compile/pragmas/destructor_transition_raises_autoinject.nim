## Test: destructorTransition auto-injects {.raises: [].} when not specified.
##
## Mirrors the {.transition.} auto-injection rule: destructors are Nim 2.x
## hooks that may not raise, so the pragma silently augments the proc's
## pragma list with {.raises: [].} when the user does not write one.
import ../../../src/typestates

type
  Token = object
    bytes: int

  Issued = distinct Token
  Revoked = distinct Token

typestate Token:
  consumeOnTransition = false
  strictTransitions = false
  states Issued, Revoked
  initial:
    Issued
  terminal:
    Revoked
  transitions:
    Issued -> Revoked

# No {.raises.} on the destructor — the macro injects {.raises: [].}.
proc `=destroy`(t: var Issued) {.destructorTransition.} =
  discard

# Indirect verification that {.raises: [].} was injected: a raising helper
# called from a {.raises: [].} proc would fail to compile. We assert this
# by writing a {.raises: [].} caller that takes a sink Issued (which would
# trigger the destructor on exit). If raises injection were absent, the
# destructor would default to inferring raises and pollute the caller.
proc consumeIssued(t: sink Issued) {.raises: [].} =
  discard t

let issued = Issued(Token(bytes: 1))
consumeIssued(issued)

verifyTypestates()
echo "destructor_transition_raises_autoinject ok"
