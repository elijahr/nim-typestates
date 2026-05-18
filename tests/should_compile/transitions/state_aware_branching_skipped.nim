## F5: Branching-return transitions are deferred to v0.6 and must NOT have
## decoys emitted. This fixture exercises a transition with multiple
## destinations (Approved | Declined). If decoys were emitted for branching
## procs they would shadow legitimate operations, so this must compile and
## run cleanly.
##
## Round-14 (Gemini r13 HIGH): the sink-param pre-population skip was
## reversed. `review`'s body produces its result via
## `toReviewResult(Approved(Application(s)))` which the analyzer
## cannot recognise as a conversion-consume (`toReviewResult` is the
## generated case-constructor, not a state-type), and the
## `Application` typestate declares no terminal states (its sole
## transition is the branching `Submitted -> (Approved | Declined)`),
## so a `{.destructorTransition.}` cannot bridge `s`. Add
## `{.skipCfgAnalysis.}` — the documented escape hatch for procs the
## analyzer cannot model. F5 decoy emission (the fixture's focus) is
## unaffected.
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

proc review(s: sink Submitted): ReviewResult {.transition, skipCfgAnalysis.} =
  toReviewResult(Approved(Application(s)))

verifyTypestates()

let s = Submitted(Application(id: 1))
let r = s.review()
doAssert r.kind == rApproved

echo "state_aware_branching_skipped test passed"
