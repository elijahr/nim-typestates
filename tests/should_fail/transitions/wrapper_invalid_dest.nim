## Test: Result[BadDest, E] with no Proposed -> BadDest edge must fail.
##
## After unwrapping Result, the inner destination `Filled` is validated
## against the Proposed -> Filled edge (which is NOT declared). The
## diagnostic must name `Filled` as the invalid destination and explain
## that it is not a declared source/destination in the typestate.
# expects: "Filled"
# expects: "is not a declared source"
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

proc bad(p: Proposed): Result[Filled, string] {.transition.} =
  ok(Filled(Order(p)))
