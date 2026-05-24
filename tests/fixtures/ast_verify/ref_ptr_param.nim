## AST-verify fixture (GROUP C, robustness): UNMARKED procs whose first param
## is `ref <State>` and `ptr <State>` on a strict typestate. The pointer
## indirection must be peeled to recognize the underlying typestate state.
##
## Correct (AST) result: TWO `fcUnmarkedProcStrict` errors (one per proc).
##
## Old text scanner: FALSE-NEGATIVE on both. Its extracted param types are the
## literals `ref Open` / `ptr Open`, neither of which is a member of `states`,
## so neither proc is matched and nothing is emitted.
import ../../../src/typestates

type
  Handle = object
  Open = distinct Handle
  Closed = distinct Handle

typestate Handle:
  consumeOnTransition = false
  states Open, Closed
  transitions:
    Open -> Closed

proc viaRef(h: ref Open) =
  discard

proc viaPtr(h: ptr Open) =
  discard
