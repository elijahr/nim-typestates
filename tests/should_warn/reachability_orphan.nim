## Reachability: orphan state warning — C has no incoming transitions and
## is not declared `initial:`. The analyzer reports it as ORPHAN (more
## specific than DEAD: the fix is to wire C up, not remove it).
# expects: "Orphan state 'C'"
# expects: "No incoming transitions and not declared `initial:`"
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
