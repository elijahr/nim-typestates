## AST-verify fixture (GROUP A): a proc on a STRICT typestate param carrying a
## COMBINED pragma block `{.raises: [], transition.}`. The proc IS a marked
## transition; the `transition` pragma shares the block with `raises`.
##
## Correct (AST) result: NO finding — `transition` is present in the block,
## and the proc is counted as a checked transition.
##
## Old text scanner: FALSE-FLAGS this. It recognizes only the exact substrings
## `{.transition.}` / `{. transition .}`. The combined block
## `{.raises: [], transition.}` matches neither, so the scanner emits a
## spurious `fcUnmarkedProcStrict` error.
import ../../../src/typestates

type
  Conn = object
  Open = distinct Conn
  Closed = distinct Conn

typestate Conn:
  consumeOnTransition = false
  states Open, Closed
  transitions:
    Open -> Closed

proc shut(c: Open): Closed {.raises: [], transition.} =
  result = Closed(c)
