## Test (CFG-001 negative — nested `Dst(move(src).Base)` conversion-consume,
## round-3 Findings #1+#2 composed): the canonical typestate transition
## body shape, but with the source explicitly `move`-wrapped before the
## `.Base` projection. Exercises the recursive composition the unified
## helper guarantees:
##
##   nnkCall(Closed, nnkDotExpr(nnkCall(move, c), File))
##
## `consumeLocalsInSubtree` walks the conversion's argument subtree; the
## DotExpr-receiver branch reduces to `nnkCall(move, c)`, which
## `extractTrackedLocal` unwraps via `isIntrinsicConsumer` to the
## underlying local `c`. Pre-fix the bespoke pattern matcher in the
## arg-iteration loop did not recurse through DotExpr + intrinsic-wrap
## combinations and could leave `c` tracked.
import ../../../src/typestates

type
  Frame = object
    n: int

  Open = distinct Frame
  Closed = distinct Frame

typestate Frame:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Closed

proc shutdown(c: sink Open): Closed {.transition.} =
  ## Nested shape `Closed(move(c).Frame)`: `move(c)` is parsed as
  ## `nnkCall(move, c)`; `.Frame` wraps it in `nnkDotExpr`; the outer
  ## `Closed(...)` is the conversion-consume call. The helper resolves
  ## the nested wrap to the underlying tracked local `c` and the
  ## conversion-consume path drops it.
  result = Closed(move(c).Frame)

proc useShutdown() {.notATransition.} =
  var c: Open
  discard shutdown(c)

verifyTypestates()
useShutdown()
echo "cfg_analyzer_conversion_consume_move ok"
