## Snippet: Payment typestate definition
## Used by docs for include-markdown

import ../../src/typestates

type
  Payment = object
    id: string
    amount: int
    authCode: string
    refundedAmount: int

  Created = distinct Payment
  Authorized = distinct Payment
  Captured = distinct Payment
  PartiallyRefunded = distinct Payment
  FullyRefunded = distinct Payment
  Settled = distinct Payment

typestate Payment:
  states Created, Authorized, Captured, PartiallyRefunded, FullyRefunded, Settled
  transitions:
    Created -> Authorized
    Authorized -> Captured
    Captured -> (PartiallyRefunded | FullyRefunded | Settled) as CaptureResult
    PartiallyRefunded -> (PartiallyRefunded | FullyRefunded | Settled) as RefundResult
    FullyRefunded -> Settled
