## Test (CFG-001 negative — `discard system.move(f)` qualified
## intrinsic-callee in discard, round-3 Finding #3): the qualified form
## `system.move(f)` parses as
## `nnkCall(nnkDotExpr(system, move), f)` with call.len == 2 and call[0]
## an `nnkDotExpr`. `isIntrinsicConsumer` recognises this as an
## intrinsic-consumer callee (via the qualified `system.move` /
## `system.sink` branch) and the discard handler routes through
## `extractTrackedLocal` to drop `f` from tracking.
##
## Pre-fix the bare-ident-only operand check missed every qualified
## wrapper shape; library code that explicitly disambiguates against
## user-defined `move` overloads via `system.move` tripped a
## false-positive CFG-001.
import ../../../src/typestates

type
  Cell = object
    n: int

  Filled = distinct Cell
  Empty = distinct Cell

typestate Cell:
  consumeOnTransition = false
  strictTransitions = false
  states Filled, Empty
  initial:
    Filled
  terminal:
    Empty
  transitions:
    Filled -> Empty

proc empty(c: sink Filled): Empty {.transition.} =
  result = Empty(c.Cell)

proc useDiscardSystemMove() {.notATransition.} =
  var c: Filled
  discard system.move(c)
  # c is consumed via the qualified intrinsic -> fall-through accepts.

verifyTypestates()
useDiscardSystemMove()
echo "cfg_analyzer_discard_system_move ok"
