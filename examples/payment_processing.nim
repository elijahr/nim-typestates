## Payment Processing with Typestates
##
## The payment processing flow is a perfect typestate example because mistakes
## are EXPENSIVE. Charge before authorization? Chargeback. Refund twice?
## Money gone. Capture an expired authorization? Failed transaction.
##
## This example models the standard payment flow:
##   Created -> Authorized -> Captured -> (Refunded | Settled)
##
## The typestate ensures you CANNOT:
## - Capture without authorizing first
## - Refund before capturing
## - Capture an already-captured payment
## - Authorize an already-authorized payment

import ../src/typestates

type
  Payment = object
    id: string
    amount: int           # cents, to avoid float issues
    currency: string
    cardToken: string
    authCode: string
    capturedAt: int64
    refundedAmount: int

  # States represent where in the lifecycle this payment is
  Created = distinct Payment      ## Just created, not yet authorized
  Authorized = distinct Payment   ## Card charged, funds held, not yet captured
  Captured = distinct Payment     ## Funds transferred to merchant
  PartiallyRefunded = distinct Payment  ## Some amount refunded
  FullyRefunded = distinct Payment      ## Entire amount refunded
  Settled = distinct Payment      ## Batch settled, funds in bank
  Voided = distinct Payment       ## Authorization cancelled before capture

typestate Payment:
  consumeOnTransition = false
  states Created, Authorized, Captured, PartiallyRefunded, FullyRefunded, Settled, Voided
  transitions:
    Created -> Authorized
    Authorized -> Captured | Voided as AuthResult
    Captured -> PartiallyRefunded | FullyRefunded | Settled as CaptureResult
    PartiallyRefunded -> PartiallyRefunded | FullyRefunded | Settled as RefundResult
    FullyRefunded -> Settled

# ============================================================================
# Transition procedures - each one enforces the state machine
# ============================================================================

proc authorize(p: Created, cardToken: string): Authorized {.transition.} =
  ## Authorize payment against the card.
  ## This places a hold on the customer's funds but doesn't transfer them.
  ## In production, this would call your payment processor API.
  var payment = p.Payment
  payment.cardToken = cardToken
  payment.authCode = "AUTH_" & payment.id
  echo "  [GATEWAY] Authorized $", payment.amount, " on card ending in ****"
  result = Authorized(payment)

proc capture(p: Authorized): Captured {.transition.} =
  ## Capture the authorized funds - money moves to merchant.
  ## Must happen within auth window (usually 7 days).
  var payment = p.Payment
  payment.capturedAt = 1234567890  # In real code: current timestamp
  echo "  [GATEWAY] Captured $", payment.amount, " (auth: ", payment.authCode, ")"
  result = Captured(payment)

proc void(p: Authorized): Voided {.transition.} =
  ## Cancel the authorization before capture.
  ## Releases the hold on customer's card - no money moved.
  echo "  [GATEWAY] Voided authorization ", p.Payment.authCode
  result = Voided(p.Payment)

proc partialRefund(p: Captured, amount: int): PartiallyRefunded {.transition.} =
  ## Refund part of the captured amount.
  var payment = p.Payment
  payment.refundedAmount = amount
  echo "  [GATEWAY] Partial refund: $", amount, " of $", payment.amount
  result = PartiallyRefunded(payment)

proc fullRefund(p: Captured): FullyRefunded {.transition.} =
  ## Refund the entire captured amount.
  var payment = p.Payment
  payment.refundedAmount = payment.amount
  echo "  [GATEWAY] Full refund: $", payment.amount
  result = FullyRefunded(payment)

proc additionalRefund(p: PartiallyRefunded, amount: int): RefundResult {.transition.} =
  ## Add more refund to a partially refunded payment.
  var payment = p.Payment
  payment.refundedAmount += amount
  echo "  [GATEWAY] Additional refund: $", amount
  if payment.refundedAmount >= payment.amount:
    result = RefundResult -> FullyRefunded(payment)
  else:
    result = RefundResult -> PartiallyRefunded(payment)

proc settle(p: Captured): Settled {.transition.} =
  ## Batch settlement - funds deposited to merchant bank.
  echo "  [GATEWAY] Settled $", p.Payment.amount, " to merchant account"
  result = Settled(p.Payment)

proc settle(p: PartiallyRefunded): Settled {.transition.} =
  ## Settle a partially refunded payment (net amount).
  let net = p.Payment.amount - p.Payment.refundedAmount
  echo "  [GATEWAY] Settled $", net, " (after refunds) to merchant account"
  result = Settled(p.Payment)

proc settle(p: FullyRefunded): Settled {.transition.} =
  ## Settle a fully refunded payment ($0 net).
  echo "  [GATEWAY] Settled $0 (fully refunded) - closing payment"
  result = Settled(p.Payment)

# ============================================================================
# Non-transition operations - query state without changing it
# ============================================================================

func amount(p: PaymentStates): int =
  ## Get the payment amount in cents.
  p.Payment.amount

func refundedAmount(p: PartiallyRefunded): int =
  ## How much has been refunded so far?
  p.Payment.refundedAmount

func remainingAmount(p: PartiallyRefunded): int =
  ## How much can still be refunded?
  p.Payment.amount - p.Payment.refundedAmount

# ============================================================================
# Example usage showing compile-time safety
# ============================================================================

when isMainModule:
  echo "=== Payment Processing Demo ===\n"

  echo "1. Creating payment for $99.99..."
  var payment = Created(Payment(
    id: "pay_abc123",
    amount: 9999,  # $99.99 in cents
    currency: "USD"
  ))

  echo "\n2. Authorizing payment..."
  let authorized = payment.authorize("card_tok_visa_4242")

  echo "\n3. Capturing funds..."
  let captured = authorized.capture()

  echo "\n4. Customer requests $25 refund..."
  let refunded = captured.partialRefund(2500)
  echo "   Remaining: $", refunded.remainingAmount()

  echo "\n5. End of day settlement..."
  let settled = refunded.settle()

  echo "\n=== Payment lifecycle complete! ===\n"

  # =========================================================================
  # COMPILE-TIME ERRORS - These are the bugs the typestate PREVENTS:
  # =========================================================================

  echo "The following bugs are caught at COMPILE TIME:\n"

  # BUG 1: Capturing without authorization
  # "Oops, we forgot to auth - charged the wrong amount!"
  # let oops1 = payment.capture()
  echo "  [PREVENTED] capture() on Created payment"

  # BUG 2: Double-capture
  # "Customer charged twice!"
  # let oops2 = captured.capture()
  echo "  [PREVENTED] capture() on already-Captured payment"

  # BUG 3: Refunding before capture
  # "Refunded money we never had!"
  # let oops3 = authorized.partialRefund(1000)
  echo "  [PREVENTED] partialRefund() on Authorized payment"

  # BUG 4: Refunding a settled payment
  # "Accounting nightmare - refund after books closed!"
  # let oops4 = settled.partialRefund(500)
  echo "  [PREVENTED] partialRefund() on Settled payment"

  # BUG 5: Voiding after capture
  # "Tried to void but money already moved!"
  # let oops5 = captured.void()
  echo "  [PREVENTED] void() on Captured payment"

  echo "\nUncomment any of the 'oops' lines above to see the compile error!"
