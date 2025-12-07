## E-commerce Order Fulfillment with Typestates
##
## Order fulfillment bugs are expensive and embarrassing:
## - Shipping before payment: lost merchandise
## - Refunding unshipped orders: process confusion
## - Double-shipping: inventory nightmare
## - Cancelling already-shipped: customer confusion
##
## This example models the complete order lifecycle.

import ../src/typestates
import std/hashes

type
  Order = object
    id: string
    customerId: string
    items: seq[(string, int, int)]  # (sku, qty, price)
    total: int
    paymentId: string
    trackingNumber: string
    cancelReason: string

  # Order states
  Cart = distinct Order           ## Items being added, not yet placed
  Placed = distinct Order         ## Order submitted, pending payment
  Paid = distinct Order           ## Payment received
  Picking = distinct Order        ## Warehouse picking items
  Packed = distinct Order         ## Items packed, ready to ship
  Shipped = distinct Order        ## Handed to carrier
  Delivered = distinct Order      ## Customer received package
  Cancelled = distinct Order      ## Order cancelled
  Returned = distinct Order       ## Items returned by customer

typestate Order:
  consumeOnTransition = false
  states Cart, Placed, Paid, Picking, Packed, Shipped, Delivered, Cancelled, Returned
  transitions:
    Cart -> Placed                     # Submit order
    Placed -> Paid | Cancelled as PaymentResult         # Pay or cancel
    Paid -> Picking | Cancelled as FulfillmentAction        # Start fulfillment or cancel (refund)
    Picking -> Packed                  # Finish picking
    Packed -> Shipped                  # Hand to carrier
    Shipped -> Delivered               # Delivery confirmed
    Delivered -> Returned              # Customer returns
    * -> Cancelled                     # Can always cancel (with appropriate handling)

# ============================================================================
# Cart Operations
# ============================================================================

proc newOrder(customerId: string): Cart =
  ## Create a new shopping cart.
  echo "  [ORDER] New cart for customer: ", customerId
  result = Cart(Order(customerId: customerId))

proc addItem(order: Cart, sku: string, qty: int, price: int): Cart {.notATransition.} =
  ## Add an item to the cart.
  var o = order.Order
  o.items.add((sku, qty, price))
  o.total += qty * price
  echo "  [ORDER] Added ", qty, "x ", sku, " @ $", price, " = $", qty * price
  result = Cart(o)

proc placeOrder(order: Cart): Placed {.transition.} =
  ## Submit the order for processing.
  var o = order.Order
  o.id = "ORD-" & $hash(o.customerId)  # Simplified ID generation
  echo "  [ORDER] Order placed: ", o.id, " (total: $", o.total, ")"
  result = Placed(o)

# ============================================================================
# Payment
# ============================================================================

proc pay(order: Placed, paymentId: string): Paid {.transition.} =
  ## Record payment for the order.
  var o = order.Order
  o.paymentId = paymentId
  echo "  [ORDER] Payment received: ", paymentId
  result = Paid(o)

proc cancelUnpaid(order: Placed, reason: string): Cancelled {.transition.} =
  ## Cancel an unpaid order (no refund needed).
  var o = order.Order
  o.cancelReason = reason
  echo "  [ORDER] Order cancelled (unpaid): ", reason
  result = Cancelled(o)

proc cancelWithRefund(order: Paid, reason: string): Cancelled {.transition.} =
  ## Cancel a paid order and process refund.
  var o = order.Order
  o.cancelReason = reason
  echo "  [ORDER] Order cancelled with refund"
  echo "  [ORDER] Refunding payment: ", o.paymentId
  result = Cancelled(o)

# ============================================================================
# Fulfillment
# ============================================================================

proc startPicking(order: Paid): Picking {.transition.} =
  ## Start warehouse picking process.
  echo "  [WAREHOUSE] Starting pick for order: ", order.Order.id
  for (sku, qty, _) in order.Order.items:
    echo "  [WAREHOUSE]   Pick ", qty, "x ", sku
  result = Picking(order.Order)

proc finishPacking(order: Picking): Packed {.transition.} =
  ## Finish packing the order.
  echo "  [WAREHOUSE] Order packed and ready for shipping"
  result = Packed(order.Order)

proc ship(order: Packed, trackingNumber: string): Shipped {.transition.} =
  ## Hand order to carrier.
  var o = order.Order
  o.trackingNumber = trackingNumber
  echo "  [SHIPPING] Order shipped!"
  echo "  [SHIPPING] Tracking: ", trackingNumber
  result = Shipped(o)

proc confirmDelivery(order: Shipped): Delivered {.transition.} =
  ## Confirm customer received the order.
  echo "  [SHIPPING] Delivery confirmed for: ", order.Order.id
  result = Delivered(order.Order)

# ============================================================================
# Returns
# ============================================================================

proc initiateReturn(order: Delivered, reason: string): Returned {.transition.} =
  ## Customer initiates a return.
  echo "  [RETURNS] Return initiated for: ", order.Order.id
  echo "  [RETURNS] Reason: ", reason
  echo "  [RETURNS] Send to: 123 Returns Center, Warehouse City"
  result = Returned(order.Order)

# ============================================================================
# Status Queries
# ============================================================================

func orderId(order: OrderStates): string =
  ## Get order ID.
  order.Order.id

func trackingNumber(order: Shipped): string =
  ## Get tracking number.
  order.Order.trackingNumber

func total(order: OrderStates): int =
  ## Get order total.
  order.Order.total

# ============================================================================
# Example Usage
# ============================================================================

when isMainModule:
  echo "=== E-commerce Order Fulfillment Demo ===\n"

  echo "1. Customer adds items to cart..."
  let cart = newOrder("cust_12345")
    .addItem("SKU-LAPTOP", 1, 99900)
    .addItem("SKU-MOUSE", 2, 2500)
    .addItem("SKU-CABLE", 3, 1000)

  echo "\n2. Customer places order..."
  let placed = cart.placeOrder()

  echo "\n3. Payment processing..."
  let paid = placed.pay("pay_ch_abc123")

  echo "\n4. Warehouse picks items..."
  let picking = paid.startPicking()

  echo "\n5. Items packed..."
  let packed = picking.finishPacking()

  echo "\n6. Shipped to customer..."
  let shipped = packed.ship("1Z999AA10123456784")

  echo "\n7. Customer receives package..."
  let delivered = shipped.confirmDelivery()

  echo "\n=== Order complete! ===\n"

  # =========================================================================
  # COMPILE-TIME ERRORS - These business logic bugs are prevented:
  # =========================================================================

  echo "The following bugs are caught at COMPILE TIME:\n"

  # BUG 1: Ship before payment
  # let bad1 = placed.ship("TRACKING")
  echo "  [PREVENTED] ship() before payment - lost merchandise!"

  # BUG 2: Refund an order that wasn't paid
  # let bad2 = placed.cancelWithRefund("changed mind")
  echo "  [PREVENTED] cancelWithRefund() on unpaid order"

  # BUG 3: Ship already-shipped order (double ship)
  # let bad3 = shipped.ship("ANOTHER-TRACKING")
  echo "  [PREVENTED] ship() twice - inventory nightmare!"

  # BUG 4: Return before delivery
  # let bad4 = shipped.initiateReturn("don't want it")
  echo "  [PREVENTED] initiateReturn() before delivery"

  # BUG 5: Continue fulfillment after cancellation
  # let cancelled = paid.cancelWithRefund("out of stock")
  # let bad5 = cancelled.startPicking()
  echo "  [PREVENTED] startPicking() after cancellation"

  # BUG 6: Pay for cart (not yet an order)
  # let bad6 = cart.pay("payment")
  echo "  [PREVENTED] pay() on Cart - order not submitted"

  echo "\nUncomment any of the 'bad' lines to see the compile error!"
