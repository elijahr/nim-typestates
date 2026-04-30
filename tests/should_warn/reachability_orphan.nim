## Reachability: orphan state warning — C has no incoming transitions and
## is not declared `initial:`. Note: in this fixture C is also unreachable
## (no path from A reaches it), so the analyzer reports it as DEAD rather
## than orphan to avoid double reporting.
# expects: "Dead state 'C'"
# expects: "Unreachable from any initial state"
import ../../src/typestates

type
  X = object
  A = distinct X
  B = distinct X
  C = distinct X

typestate X:
  consumeOnTransition = false
  states A, B, C
  initial:
    A
  transitions:
    A -> B

proc go(x: A): B {.transition.} =
  B(X(x))

echo "reachability_orphan compiled"
