## Test: {.transition.} validates through a Result[T, E] wrapper.
##
## `Result[PreChecked, string]` should unwrap to `PreChecked`, so the
## Proposed -> PreChecked edge is matched.
import results
import ../../../src/typestates

type
  Order = object
    id: int

  Proposed = distinct Order
  PreChecked = distinct Order

typestate Order:
  consumeOnTransition = false
  strictTransitions = false
  states Proposed, PreChecked
  transitions:
    Proposed -> PreChecked

proc preCheck(p: Proposed): Result[PreChecked, string] {.transition.} =
  ok(PreChecked(Order(p)))

let p = Proposed(Order(id: 1))
let r = p.preCheck()
doAssert r.isOk
doAssert r.get is PreChecked
echo "wrapper_result_return test passed"
