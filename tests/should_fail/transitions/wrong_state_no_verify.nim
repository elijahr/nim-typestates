## F5: Negative test for the `verifyTypestates()` opt-in gate.
##
## Mirror of `wrong_state_simple.nim`, EXCEPT this fixture intentionally
## omits `verifyTypestates()`. The state-aware decoy procs are emitted ONLY
## when a module opts in; without the call, calling a transition on the
## wrong state must still fail compilation, but with Nim's GENERIC
## type-mismatch diagnostic — NOT the F5 tailored message.
##
## This guards two regressions:
##   1. `verifyTypestates()` becoming a no-op (the F5 tailored substring
##      would appear in the no-verify case, which we forbid below by
##      requiring the generic substring instead — a tailored message
##      would not contain "type mismatch" wording).
##   2. Decoy emission becoming always-on (would change the diagnostic
##      shape from "type mismatch" to the F5 tailored message).
# expects: "type mismatch"
import ../../../src/typestates

type
  Door = object
    id: int

  Closed = distinct Door
  Open = distinct Door
  Locked = distinct Door

typestate Door:
  consumeOnTransition = false
  strictTransitions = false
  states Closed, Open, Locked
  transitions:
    Closed -> Open
    Open -> Locked

proc unlock(d: sink Closed): Open {.transition.} =
  Open(Door(d))

proc lock(d: sink Open): Locked {.transition.} =
  Locked(Door(d))

# Note: NO verifyTypestates() call. Decoys are not emitted; Nim's stock
# overload-resolution failure must surface instead.

let c = Closed(Door(id: 1))
discard c.lock() # WRONG STATE — expect Nim's generic type mismatch.
