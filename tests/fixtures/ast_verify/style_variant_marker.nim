## AST-verify fixture (style-insensitivity, pragma markers): a proc on a STRICT
## typestate param is marked with the `notATransition` pragma written in a
## DIFFERENT Nim style (`not_a_transition`). Nim treats pragma identifiers
## style-insensitively, so `not_a_transition` is the SAME marker as
## `notATransition` (same first letter `n`, underscores ignored, rest folded)
## and must be recognized as the marker.
##
## Correct (AST) result: NO finding — the proc IS marked notATransition.
##
## Regression guard: a verifier that compares the RAW marker identifier against
## the literal `"notATransition"` would not recognize `not_a_transition` and
## would false-flag this proc with a spurious `fcUnmarkedProcStrict` error.
import ../../../src/typestates

type
  Sock = object
  Open = distinct Sock
  Closed = distinct Sock

typestate Sock:
  consumeOnTransition = false
  states Open, Closed
  transitions:
    Open -> Closed

proc peek(s: Open): int {.not_a_transition.} =
  result = 0
