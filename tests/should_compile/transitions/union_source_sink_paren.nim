## Test: Union source wrapped in `sink` or explicit parentheses still
## splits into individual sources for transition validation.
##
## Regression bar for the `extractAllSourceTypeNames` modifier/paren
## stripping: `sink (A | B)` and `(A | B)` must be equivalent to `A | B`
## at the transition pragma, not treated as opaque leaves that the graph
## can't resolve.
import ../../../src/typestates

type
  Order = object
    id: int

  Open = distinct Order
  PartiallyFilled = distinct Order
  Cancelling = distinct Order

typestate Order:
  consumeOnTransition = false
  strictTransitions = false
  states Open, PartiallyFilled, Cancelling
  transitions:
    Open -> Cancelling
    PartiallyFilled -> Cancelling

proc cancelSink(o: sink (Open | PartiallyFilled)): Cancelling {.transition.} =
  Cancelling(Order(o))

proc cancelParen(o: (Open | PartiallyFilled)): Cancelling {.transition.} =
  Cancelling(Order(o))

let o1 = Open(Order(id: 1))
let cancelledSink = o1.cancelSink()
doAssert cancelledSink is Cancelling

let o2 = Open(Order(id: 2))
let cancelledParen = o2.cancelParen()
doAssert cancelledParen is Cancelling

echo "union_source_sink_paren test passed"
