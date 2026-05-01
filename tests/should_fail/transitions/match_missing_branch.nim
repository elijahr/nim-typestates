## F4: match missing a branch — exhaustiveness error.
# expects: "not all cases are covered"
# expects: "pPendingReview"
import ../../../src/typestates

type
  Payment = object
    id: string

  Created = distinct Payment
  Approved = distinct Payment
  Declined = distinct Payment
  PendingReview = distinct Payment

typestate Payment:
  states Created, Approved, Declined, PendingReview
  transitions:
    Created -> (Approved | Declined | PendingReview) as ProcessResult

proc process(p: sink Created): ProcessResult {.transition.} =
  ProcessResult(kind: pApproved, approved: Approved(Payment(p)))

var r = Created(Payment(id: "p1")).process()
match r:
  Approved(a):
    discard
  Declined(d):
    discard
# Missing PendingReview — must fail exhaustiveness.
