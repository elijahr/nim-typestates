## AST-verify fixture (nkAccQuoted routine names): an UNMARKED routine on a
## STRICT typestate param whose name is a backticked operator (`[]`). The
## routine name parses as `nkAccQuoted`, which the routine-name extractor must
## render to a sensible symbol (`` `[]` ``) rather than an empty/anonymous name.
##
## Correct (AST) result: ONE `fcUnmarkedProcStrict` error (the routine is an
## unmarked state proc on a strict typestate), and — at the helper level — the
## classified routine must carry a non-empty operator name.
##
## Regression guard: a routine-name extractor that ignores `nkAccQuoted` would
## emit an empty name in findings/classification output.
import ../../../src/typestates

type
  Vec = object
  Open = distinct Vec
  Closed = distinct Vec

typestate Vec:
  consumeOnTransition = false
  states Open, Closed
  transitions:
    Open -> Closed

proc `[]`(s: var Open; i: int) =
  discard
