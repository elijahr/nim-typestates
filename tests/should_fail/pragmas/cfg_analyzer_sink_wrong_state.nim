## Test (call-site type mismatch — Finding #1 sink-consume guard): a
## sink-consuming transition call against a local in the WRONG source
## state must fail. Two possible diagnostic shapes:
##
##  (a) Nim's overload resolution rejects with the F5-emitted decoy
##      `{.error.}` proc (state-aware diagnostic naming the wrong
##      state). This is the preferred shape when the registered
##      transition has F5 emission applicable.
##
##  (b) Nim's plain "type mismatch" if F5 was skipped (generic /
##      branching / union-source proc).
##
## Either shape proves the typestate type system is intact AND that
## the CFG analyzer's call-tracking does NOT silently rewrite the
## local's state when the call is rejected upstream.
##
## Pattern exercised:
##
##   var c: Released         # tracked as Released (terminal already)
##   discard unpin(c)        # unpin: Pinned -> Released; called on
##                            # Released -> wrong source state.
##
## The state-aware error decoy emits a tailored message.
# expects: "Released"
import ../../../src/typestates

type
  Pin = object
    n: int

  Pinned = distinct Pin
  Released = distinct Pin

typestate Pin:
  consumeOnTransition = false
  strictTransitions = false
  states Pinned, Released
  initial:
    Pinned
  terminal:
    Released
  transitions:
    Pinned -> Released

proc unpin(p: sink Pinned): Released {.transition.} =
  result = Released(p.Pin)

proc misuse() {.notATransition.} =
  var c: Released
  discard unpin(c)

verifyTypestates()
