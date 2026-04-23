## Test: Union source parameter (two states) on {.transition.} compiles.
##
## Both Open and PartiallyFilled have a declared transition to Cancelling,
## so a single proc accepting the union `Open | PartiallyFilled` must compile.
import ../../../src/typestates

type
  Order = object
    id: int

  Open = distinct Order
  PartiallyFilled = distinct Order
  Cancelling = distinct Order
  Cancelled = distinct Order

typestate Order:
  consumeOnTransition = false
  strictTransitions = false
  states Open, PartiallyFilled, Cancelling, Cancelled
  transitions:
    Open -> PartiallyFilled
    Open -> Cancelling
    PartiallyFilled -> Cancelling
    Cancelling -> Cancelled

proc cancel(o: Open | PartiallyFilled): Cancelling {.transition.} =
  Cancelling(Order(o))

let o = Open(Order(id: 1))
let c = o.cancel()
doAssert c is Cancelling
echo "c3_union_two_sources test passed"
