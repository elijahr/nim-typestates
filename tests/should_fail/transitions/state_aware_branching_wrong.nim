## F5: Branching-return transitions are deferred to v0.6 — decoys MUST
## NOT be emitted for them. Calling such a transition with the wrong
## source state must still fail compilation, but with Nim's GENERIC
## type-mismatch diagnostic, not the F5 tailored message.
##
## If decoy emission ever expands to cover branching procs, this test
## breaks because the error string changes shape (and the tailored
## decoy would compile-error a different way that lacks "type mismatch").
##
## Round-14 (Gemini r13 HIGH): the sink-param pre-population skip was
## reversed. `s: sink Submitted` is now tracked in `review`'s body;
## the body produces its result via `toReviewResult(Approved(...))`
## which is not a recognised conversion-consume callee
## (`toReviewResult` is the generated case-constructor, not a
## state-type), and the typestate `Application` declares no
## terminal states (its sole transition is the branching
## `Submitted -> (Approved | Declined) as ReviewResult`), so a
## `{.destructorTransition.}` cannot be registered for `Submitted`.
## `{.skipCfgAnalysis.}` (the documented escape hatch for procs the
## analyzer cannot model) suppresses the body walk. The fixture's
## type-mismatch target is at the CALL SITE (`a.review()` where
## `a: Approved`), unaffected by the body-walk suppression.
# expects: "type mismatch"
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

# Wrong source: pass an Approved into review(), which expects Submitted.
# A decoy would surface as the F5 tailored "Cannot call 'review' on a
# value in state 'Approved'…" — but branching transitions are skipped,
# so we expect the GENERIC Nim diagnostic instead.
let a = Approved(Application(id: 1))
discard a.review()
