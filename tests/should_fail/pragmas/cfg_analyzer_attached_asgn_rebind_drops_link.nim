## Test (CFG-001 positive — §3.7 attached `var` param leaked at
## return, NO destructor): a registered `{.transition.}` proc takes a
## state-typed `sink BadgeIssued` first param AND a `var
## BadgeHolder` attached param. No destructor is registered for
## `BadgeHolder`. The proc returns early without consuming `b` and
## without a destructor to cover the leak — round-6 live-set pre-pop
## tracks `b` with stateType=BadgeIssued AND attachedTypeName=
## BadgeHolder; the return exit-edge's destructor lookup misses
## under EITHER key. CFG-001 fires.
##
## Round-6 regression test. Pre-fix `extractTypestatedParams`
## bailed on `var BadgeHolder` (findTypestateForState returned none
## for the attached object type name, and the path-(b) fallback was
## missing), so the attached param was never tracked. Result:
## pre-fix this fixture compiled clean and the leak escaped the
## analyzer.
##
## Locks in finding #6 (live-set pre-pop) AND finding #1 (
## TypestatedParam.attachedTypeName population in
## extractTypestatedParams's path-(b) branch).
# expects: "has not reached a terminal state"
# expects: "BadgeIssued"
# expects: "BadgeContext"
import ../../../src/typestates

type
  BadgeIssued = object
  BadgeRevoked = object

typestate BadgeContext:
  consumeOnTransition = false
  strictTransitions = false
  states BadgeIssued, BadgeRevoked
  initial:
    BadgeIssued
  terminal:
    BadgeRevoked
  transitions:
    BadgeIssued -> BadgeRevoked

# Attached object — NO destructorTransition registered against it.
type BadgeHolder {.BadgeContext: BadgeIssued.} = object
  payload: int

proc leakingHandler(
    src: sink BadgeIssued, b: var BadgeHolder, skip: bool
): BadgeRevoked {.transition.} =
  ## Attached `var BadgeHolder` param: round-6 fix tracks `b` with
  ## stateType=BadgeIssued, attachedTypeName=BadgeHolder. No
  ## destructor is registered against EITHER key, so the early
  ## return exit-edge fires CFG-001 naming `b`.
  if skip:
    return # CFG-001: 'b' is still BadgeIssued, no destructor.
  result = BadgeRevoked()
  discard b.payload

verifyTypestates()
