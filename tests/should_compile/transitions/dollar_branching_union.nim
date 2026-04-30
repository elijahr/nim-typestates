## F3: $ overload for branching union types.
import ../../../src/typestates

type
  Payment = object
    id: string

  Created = distinct Payment
  PartiallyRefunded = distinct Payment
  FullyRefunded = distinct Payment
  Settled = distinct Payment

typestate Payment:
  consumeOnTransition = false
  states Created, PartiallyRefunded, FullyRefunded, Settled
  transitions:
    Created -> (PartiallyRefunded | FullyRefunded | Settled) as CaptureResult

proc capture(p: Created): CaptureResult {.transition.} =
  CaptureResult(kind: cSettled, settled: Settled(Payment(p)))

# Settled branch
block:
  let c = Created(Payment(id: "p1"))
  let r = c.capture()
  doAssert $r == "Settled"

# PartiallyRefunded branch
block:
  let r = CaptureResult(
    kind: cPartiallyRefunded, partiallyrefunded: PartiallyRefunded(Payment(id: "p2"))
  )
  doAssert $r == "PartiallyRefunded"

# FullyRefunded branch
block:
  let r =
    CaptureResult(kind: cFullyRefunded, fullyrefunded: FullyRefunded(Payment(id: "p3")))
  doAssert $r == "FullyRefunded"

echo "dollar_branching_union test passed"
