## F5: Branching-return transitions are deferred to v0.6 and must NOT have
## decoys emitted. This fixture exercises a transition with multiple
## destinations (Approved | Declined). If decoys were emitted for branching
## procs they would shadow legitimate operations, so this must compile and
## run cleanly.
import ../../../src/typestates

type
  Application = object
    id: int

  Submitted = distinct Application
  Approved = distinct Application
  Declined = distinct Application

typestate Application:
  consumeOnTransition = false
  strictTransitions = false
  states Submitted, Approved, Declined
  transitions:
    Submitted -> (Approved | Declined) as ReviewResult

proc review(s: sink Submitted): ReviewResult {.transition.} =
  toReviewResult(Approved(Application(s)))

verifyTypestates()

let s = Submitted(Application(id: 1))
let r = s.review()
doAssert r.kind == rApproved

echo "state_aware_branching_skipped test passed"
