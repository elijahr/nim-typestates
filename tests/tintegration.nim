## Comprehensive integration test for all features

import ../src/typestates

# Full-featured typestate with all defaults
type
  Order = object
    id: string
    total: int

  Pending = distinct Order
  Paid = distinct Order
  Shipped = distinct Order
  Delivered = distinct Order

typestate Order:
  consumeOnTransition = false # Opt out for existing tests
  # strictTransitions = true (default)
  # All typestates are sealed (no extension allowed)
  states Pending, Paid, Shipped, Delivered
  transitions:
    Pending -> Paid
    Paid -> Shipped
    Shipped -> Delivered
    Shipped -> Shipped # Self-transition: update tracking

# Transitions
proc pay(o: Pending): Paid {.transition.} =
  result = Paid(o.Order)

proc ship(o: Paid): Shipped {.transition.} =
  result = Shipped(o.Order)

proc updateTracking(o: Shipped): Shipped {.transition.} =
  result = o # Self-transition

proc deliver(o: Shipped): Delivered {.transition.} =
  result = Delivered(o.Order)

# Non-transitions
proc total(o: Pending): int {.notATransition.} =
  result = o.Order.total

proc id(o: Paid): string {.notATransition.} =
  result = o.Order.id

# Verify
verifyTypestates()

# Test flow
let order = Pending(Order(id: "ORD-123", total: 9999))
doAssert order.total() == 9999

let paid = order.pay()
doAssert paid.id() == "ORD-123"

var shipped = paid.ship()
shipped = shipped.updateTracking() # Self-transition
shipped = shipped.updateTracking() # Again

let delivered = shipped.deliver()

echo "integration test passed"
