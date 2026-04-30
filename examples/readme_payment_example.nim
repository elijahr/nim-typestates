## Regression lock for the README front-page payment example.
## Mirrors README.md lines 11-43 exactly; only the import path differs
## (relative path here, package import in the README).
## Any change that breaks this fixture breaks the front page.

import ../src/typestates

type
  Payment = object
    id: string
    amount: int

  Created = distinct Payment
  Authorized = distinct Payment
  Captured = distinct Payment

typestate Payment:
  states Created, Authorized, Captured
  transitions:
    Created -> Authorized
    Authorized -> Captured

proc authorize(p: sink Created): Authorized {.transition.} =
  Authorized(Payment(p))

proc capture(p: sink Authorized): Captured {.transition.} =
  Captured(Payment(p))

proc main() =
  let payment = Created(Payment(id: "pay_123", amount: 9999))
  let authed = payment.authorize()
  let captured = authed.capture()

  # payment.capture()  # type mismatch: got 'Created' but expected 'Authorized'

main()
