## Test (Round-7 Finding #2, CFG-003 positive — `discard f.move()` of a
## non-terminal tracked local with no covering destructor must fire
## CFG-003): the dot-call intrinsic-consumer shape `f.move()` is the
## method-call sugar form of `move(f)`. Pre-round-7 the analyzer's
## discard handler captured pre-walk state via `extractTrackedLocal`,
## which only recognised the prefix-form intrinsic shape
## (`n.len == 2 and isIntrinsicConsumer(n[0])`) and returned
## `none(string)` for the dot-call shape (`n.len == 1`, callee is a
## DotExpr).
##
## Consequence pre-fix: `preWalkStateName` was empty for `discard
## f.move()`. The operand walk then consumed `f` (via the round-5
## intrinsic-arg drop in `applyCallTransitions`), but with no
## pre-walk capture the CFG-003 non-terminal-discard check at the
## discard site fell through entirely — a non-terminal local with no
## covering destructor was silently allowed to be `discard`-consumed
## via the dot-call intrinsic. Same loss-of-validation pattern as the
## round-5 Finding #3 prefix-form CFG-003 bypass, this time for the
## dot-call sugar shape.
##
## Post-round-7: `extractTrackedLocal` for `nnkCommand`/`nnkCall`
## routes through `intrinsicConsumerArg`, which yields the receiver
## `f` for the dot-call shape. Pre-walk state is captured, post-walk
## the local is consumed, and the CFG-003 lookup observes the
## pre-walk state — non-terminal with no destructor -> ERROR.
##
## Same-class lineage: the round-5 unification covered the
## `isIntrinsicConsumer` recognizer and the `applyCallTransitions`
## consumed-arg drop. Round-7 closes the helper-coverage gap in
## `extractTrackedLocal` so the discard pre-walk capture and the
## call-arg resolution observe the same dot-call shape uniformly.
# expects: "is not allowed"
# expects: "not a terminal state"
# expects: "Open"
# expects: "Resource"
import ../../../src/typestates

type
  Resource = object
    n: int

  Open = distinct Resource
  Closed = distinct Resource

typestate Resource:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Closed

proc shutdown(r: sink Open): Closed {.transition.} =
  ## Drives a Resource Open value into terminal. Defined so the
  ## typestate has a real transition; not called from the leaking
  ## proc's body.
  result = Closed(r.Resource)

proc leakViaDiscardDotCallMove(seed: sink Open): Closed {.transition.} =
  ## Drive `seed` to terminal via the result construction. Introduce a
  ## NEW body-local `f` (Open, non-terminal, NO covering destructor)
  ## and `discard f.move()` it. The dot-call intrinsic transfers `f`'s
  ## value to a discarded temporary, dropping `f` from the live-set
  ## (handled by `applyCallTransitions`'s intrinsic-arg block, via
  ## round-5's `intrinsicConsumerArg` unification). But the discard
  ## handler's CFG-003 non-terminal-discard check must observe `f`'s
  ## PRE-walk state (Open) and reject — `discard` of a typestate
  ## value that is not a terminal state, with no `{.destructor-
  ## Transition.}` to bridge, is forbidden.
  ##
  ## Pre-fix this fixture silently passed because the dot-call shape
  ## was invisible to `extractTrackedLocal` at the pre-walk capture
  ## site; `preWalkStateName` was empty, the CFG-003 branch was
  ## skipped, and the operand walk's intrinsic-arg drop hid the
  ## violation. Post-fix the helper resolves `f.move()` to `f`, the
  ## pre-walk state is captured, and the discard-site check fires.
  result = Closed(seed.Resource)
  var f: Open
  discard f.move()

verifyTypestates()
