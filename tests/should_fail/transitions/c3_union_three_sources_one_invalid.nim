## Test: Union with three sources, one of which has no edge to dest.
##
## Start and Middle both have edges to Final, but Other does NOT. The
## diagnostic must name `Other` as the invalid source AND describe the
## failing edge (so the substring survives beyond the union pretty-print).
# expects: "Other"
# expects: "is not a declared source of"
import ../../../src/typestates

type
  Pipeline = object
    step: int

  Start = distinct Pipeline
  Middle = distinct Pipeline
  Other = distinct Pipeline
  Final = distinct Pipeline

typestate Pipeline:
  consumeOnTransition = false
  strictTransitions = false
  states Start, Middle, Other, Final
  transitions:
    Start -> Middle
    Start -> Final
    Middle -> Final
    Start -> Other

proc finish(p: Start | Middle | Other): Final {.transition.} =
  Final(Pipeline(p))
