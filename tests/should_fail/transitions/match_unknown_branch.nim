## F4: match references a state not in the union.
# expects: "unknown branch"
# expects: "Bogus"
import ../../../src/typestates

type
  Payment = object
    id: string

  Created = distinct Payment
  Approved = distinct Payment
  Declined = distinct Payment

typestate Payment:
  states Created, Approved, Declined
  transitions:
    Created -> (Approved | Declined) as ProcessResult

proc process(p: sink Created): ProcessResult {.transition.} =
  ProcessResult(kind: pApproved, approved: Approved(Payment(p)))

var r = Created(Payment(id: "p1")).process()
match r:
  Approved(a):
    discard
  Bogus(q):
    discard
  Declined(d):
    discard
