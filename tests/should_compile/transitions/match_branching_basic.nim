## F4: basic three-way match over a branching union.
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
var label = ""
match r:
  Approved(a):
    label = "Approved"
  Declined(d):
    label = "Declined"
  PendingReview(pr):
    label = "PendingReview"

doAssert label == "Approved"
echo "match_branching_basic test passed"
