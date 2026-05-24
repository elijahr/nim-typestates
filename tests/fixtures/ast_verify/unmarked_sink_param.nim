## AST-verify fixture (GROUP B): an UNMARKED proc whose first param is
## `sink <State>` on a STRICT typestate. The `sink` modifier must be peeled to
## recognize the underlying typestate state.
##
## Correct (AST) result: ONE `fcUnmarkedProcStrict` error.
##
## Old text scanner: FALSE-NEGATIVE. Its extracted param type is the literal
## `sink Open`, which is not a member of `states`, so it never matches and
## emits nothing.
import ../../../src/typestates

type
  Door = object
  Open = distinct Door
  Closed = distinct Door

typestate Door:
  consumeOnTransition = false
  states Open, Closed
  transitions:
    Open -> Closed

proc consume(f: sink Open) =
  discard
