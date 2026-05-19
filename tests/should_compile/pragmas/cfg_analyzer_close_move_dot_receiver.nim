## Test (CFG-001 negative — round-3 #1+#2 composed conversion-consume of
## `move(f).Base`): inside a transition body the result is produced via
## the conversion-consume idiom `Dst(move(src).Base)`, which combines an
## intrinsic-callee wrap on the source with a `.Base` projection inside
## a state-type conversion. The helper resolves the nested
## `nnkDotExpr(nnkCall(move, src), Base)` shape to the underlying
## tracked local `src`, and `consumeLocalsInSubtree` drops it.
##
## Pre-fix neither the per-arg pattern matcher (which only handled bare
## ident or `nnkCommand(move, ident)`) nor the conversion-consume early
## return (which iterated `consumeLocalsInSubtree` only on
## `call[1..N-1]`) descended through DotExpr + intrinsic-wrap
## combinations cleanly.
import ../../../src/typestates

type
  Buffer = object
    n: int

  Open = distinct Buffer
  Closed = distinct Buffer

typestate Buffer:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Closed

proc seal(b: sink Open): Closed {.transition.} =
  ## Body uses `Closed(move(b).Buffer)`: outer call is the state-type
  ## conversion `Closed(...)`, inner argument is
  ## `nnkDotExpr(nnkCall(move, b), Buffer)`. Helper resolves to `b`;
  ## conversion-consume drops it.
  result = Closed(move(b).Buffer)

proc useSeal() {.notATransition.} =
  var b: Open
  discard seal(b)

verifyTypestates()
useSeal()
echo "cfg_analyzer_close_move_dot_receiver ok"
