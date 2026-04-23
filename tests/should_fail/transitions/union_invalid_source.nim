## Test: Union source with one invalid source must fail.
##
## Filled has no declared transition to Cancelling, so a proc accepting
## `Open | Filled` -> Cancelling must fail with a diagnostic naming both
## the invalid source (`Filled`) and the destination (`Cancelling`).
# expects: "Filled"
# expects: "Cancelling"
import ../../../src/typestates

type
  Order = object
    id: int

  Open = distinct Order
  Filled = distinct Order
  Cancelling = distinct Order

typestate Order:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Filled, Cancelling
  transitions:
    Open -> Filled
    Open -> Cancelling

proc cancel(o: Open | Filled): Cancelling {.transition.} =
  Cancelling(Order(o))
