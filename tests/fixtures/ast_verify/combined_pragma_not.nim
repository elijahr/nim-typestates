## AST-verify fixture (GROUP A): a proc on a STRICT typestate param carrying a
## COMBINED pragma block `{.discardable, raises: [], notATransition.}`. The
## proc IS marked notATransition; it just shares the pragma block with other
## pragmas.
##
## Correct (AST) result: NO finding — `notATransition` is present in the
## pragma block.
##
## Old text scanner: FALSE-FLAGS this. It only recognizes the exact substrings
## `{.notATransition.}` / `{. notATransition .}`. The combined block
## `{.discardable, raises: [], notATransition.}` contains neither literal, so
## the scanner concludes the proc is unmarked and emits a spurious
## `fcUnmarkedProcStrict` error.
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

proc inspect(c: Open): int {.discardable, raises: [], notATransition.} =
  result = 0
