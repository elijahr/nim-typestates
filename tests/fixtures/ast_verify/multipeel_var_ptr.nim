## AST-verify fixture (pepper edge-flag 2c — multi-peel guard): an UNMARKED
## proc whose first param is `var ptr <State>` on a STRICT typestate. The peel
## must traverse BOTH the `var` and the `ptr` wrappers (nkVarTy(nkPtrTy(State)))
## to reach the underlying state base, so the unmarked proc is flagged.
##
## Correct (AST) result: ONE `fcUnmarkedProcStrict` error.
##
## Old text scanner: FALSE-NEGATIVE. Its extracted param type is the literal
## `var ptr Open`, which is not a member of `states`, so nothing is emitted.
import ../../../src/typestates

type
  Buf = object
  Open = distinct Buf
  Closed = distinct Buf

typestate Buf:
  consumeOnTransition = false
  states Open, Closed
  transitions:
    Open -> Closed

proc poke(b: var ptr Open) =
  discard
