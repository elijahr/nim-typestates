## Test: Future[Result[BadDest, E]] with no underlying edge must fail.
##
## Double-unwrap Future -> Result -> Filled. The typestate declares
## only Proposed -> PreChecked, so `Proposed -> Filled` is not a
## declared edge. The diagnostic must name `Filled`.
# expects: "Filled"
import chronos
import results
import ../../../src/typestates

type
  Order = object
    id: int

  Proposed = distinct Order
  PreChecked = distinct Order
  Filled = distinct Order

typestate Order:
  consumeOnTransition = false
  strictTransitions = false
  states Proposed, PreChecked, Filled
  transitions:
    Proposed -> PreChecked

proc bad(p: Proposed): Future[Result[Filled, string]] {.async, transition.} =
  return ok(Filled(Order(p)))
