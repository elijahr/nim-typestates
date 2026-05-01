## F5: Negative control — legitimate transitions must still resolve correctly
## when state-aware error decoys are emitted alongside them. The decoys must
## not shadow the real proc on the correct source state.
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

# lvalue form
let c = Closed(Door(id: 1))
let o = c.unlock()
let l1 = o.lock()
doAssert l1 is Locked

# rvalue (chained) form
let l2 = Closed(Door(id: 2)).unlock().lock()
doAssert l2 is Locked

echo "state_aware_correct_call test passed"
