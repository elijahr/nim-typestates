## Test (CFG-001 negative — dot-call with `move(arg)` extra parameter,
## round-3 Findings #1+#2 composed): the analyzer must recognise the
## combination of a dot-call shape (round-2 #1, receiver as implicit
## first arg) AND an extra argument wrapped in `nnkCall(move, x)`
## (round-3 #2, parens form).
##
## Pattern: `receiver.method(move(extra))` — call shape is
## `nnkCall(nnkDotExpr(receiver, method), nnkCall(move, extra))`.
## The dot-call path folds `receiver` into `argNodes[0]` and `move(extra)`
## into `argNodes[1]`. The unified `extractTrackedLocal` helper resolves
## the inner `nnkCall(move, extra)` to `extra` (via `isIntrinsicConsumer`).
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

proc merge(a, b: sink Open): Closed {.transition.} =
  ## Consumes both inputs to terminal. Round-14: the sink-param
  ## pre-population skip was reversed; `b` is now tracked in the
  ## live-set, so `discard b` (pre-round-14) would fire CFG-003 on
  ## the non-terminal Open value. Replace with an explicit
  ## conversion-consume `discard Closed(b.Pipe)` that routes `b` to
  ## its registered terminal via the conversion-consume path,
  ## mirroring how `a` is consumed in the result expression.
  discard Closed(b.Pipe)
  result = Closed(a.Pipe)

proc useDotCallMoveArg() {.notATransition.} =
  var a: Open
  var b: Open
  discard a.merge(move(b))
  # a (receiver) and b (move-wrapped) both consumed -> fall-through accepts.

verifyTypestates()
useDotCallMoveArg()
echo "cfg_analyzer_dot_call_move_arg ok"
