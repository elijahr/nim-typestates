## Test (Round-7 Finding #2, CFG-001 negative — dot-call intrinsic
## `f.move()` used as an argument to a registered transition call):
## the canonical Nim ownership-transfer idiom `close(f.move())` passes
## the move-wrapped local to a sink-parameter transition. The
## analyzer's `buildArgStatesFromCall` resolves each arg via
## `extractTrackedLocal`; pre-round-7 the helper's `nnkCommand`/`nnkCall`
## branch only matched the prefix shape `move(f)` (gated on
## `n.len == 2`) and returned `none(string)` for the dot-call shape
## `f.move()` (parsed as `nnkCall(nnkDotExpr(f, move))`, where
## `n.len == 1` and the callee IS the DotExpr).
##
## Consequence pre-fix: the per-arg loop in `applyCallTransitions`
## could not resolve the `f.move()` arg to the underlying local `f`,
## so the registered-transition lookup ran with no source-state
## context, and `close`'s consumption of its arg was not reflected in
## the live-set. `f` therefore survived to the next fall-through edge
## with its pre-call non-terminal state, false-firing CFG-001 on the
## idiomatic pipe-style consumption pattern.
##
## Post-round-7: `extractTrackedLocal` for `nnkCommand`/`nnkCall`
## delegates to `intrinsicConsumerArg`, which uniformly handles
## prefix, qualified-prefix, AND dot-call sugar — yielding `f` as the
## consumed argument for `f.move()`. `applyCallTransitions` then
## resolves the arg to `f`, advances/consumes per the registered
## transition spec, and the fall-through accepts.
##
## Same-class lineage: round-5 Finding #2 unified `isIntrinsicConsumer`
## to recognise the dot-call callee shape; round-7 extends the
## unification to the helper that resolves the consumed-argument
## position downstream.
import ../../../src/typestates

type
  Pipe = object
    n: int

  Open = distinct Pipe
  Closed = distinct Pipe

typestate Pipe:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Closed

proc close(f: sink Open): Closed {.transition.} =
  result = Closed(f.Pipe)

proc useDotCallAsCallArg(src: sink Open): Closed {.transition.} =
  ## Drive `src` to terminal via `close(src.move())`. The dot-call
  ## intrinsic `src.move()` is the argument to a registered transition;
  ## the analyzer must resolve the arg to `src` (via
  ## `intrinsicConsumerArg`-routed `extractTrackedLocal`) and apply
  ## `close`'s consumption. Pre-fix this fall-through false-fired
  ## CFG-001 against `src` because the arg-resolution missed the
  ## dot-call shape. Post-fix `src` is consumed, `result` is bound to
  ## the call's value, and the fall-through accepts.
  result = close(src.move())

verifyTypestates()
echo "cfg_analyzer_dot_call_intrinsic_as_call_arg ok"
