## Reachability: trap state warning — A enters Loop1, which can only
## bounce between Loop1 and Loop2. Neither reaches the declared terminal
## state Done.
# expects: "Trap state 'Loop1'"
# expects: "Trap state 'Loop2'"
# expects: "cannot reach any terminal state"
import ../../src/typestates

type
  X = object
  A = distinct X
  Loop1 = distinct X
  Loop2 = distinct X
  Done = distinct X

typestate X:
  consumeOnTransition = false
  states A, Loop1, Loop2, Done
  initial:
    A
  terminal:
    Done
  transitions:
    A -> Loop1
    Loop1 -> Loop2
    Loop2 -> Loop1

proc go1(x: A): Loop1 {.transition.} =
  Loop1(X(x))

proc go2(x: Loop1): Loop2 {.transition.} =
  Loop2(X(x))

proc go3(x: Loop2): Loop1 {.transition.} =
  Loop1(X(x))

echo "reachability_trap compiled"
