## Test (CFG-001 negative — qualified `close(system.move(f))` arg-shape,
## round-3 Finding #2): a registered transition called with its argument
## wrapped in the qualified intrinsic `system.move(f)` must consume `f`.
##
## Parsed shape: `nnkCall(close, nnkCall(nnkDotExpr(system, move), f))`.
## The `extractTrackedLocal` helper recognises `nnkDotExpr(system, move)`
## as an intrinsic-consumer callee (via `isIntrinsicConsumer`) and unwraps
## the wrapper to the underlying `f`. Pre-fix the bespoke arg-shape
## matcher only knew bare `move`/`sink` idents and missed every qualified
## form, leaving `f` falsely tracked at the caller.
import ../../../src/typestates

type
  Frame = object
    n: int

  Live = distinct Frame
  Done = distinct Frame

typestate Frame:
  consumeOnTransition = false
  strictTransitions = false
  states Live, Done
  initial:
    Live
  terminal:
    Done
  transitions:
    Live -> Done

proc finish(f: sink Live): Done {.transition.} =
  result = Done(f.Frame)

proc useQualifiedMove() {.notATransition.} =
  var f: Live
  discard finish(system.move(f))

verifyTypestates()
useQualifiedMove()
echo "cfg_analyzer_close_system_move_arg ok"
