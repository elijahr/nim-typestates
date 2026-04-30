## F5: Calling a transition with the wrong source state must fail with a
## tailored, state-aware error message rather than a generic type mismatch.
##
## A `lock` transition expects an `Open` door. Calling it on a `Closed` door
## must trigger a state-aware decoy proc that fires `{.error.}` with a message
## naming the proc, the wrong state, and the expected state.
# expects: "Cannot call 'lock' on a value in state 'Closed'. Expected 'Open'."
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

verifyTypestates()

let c = Closed(Door(id: 1))
discard c.lock() # WRONG STATE — should fail with the F5 tailored error
