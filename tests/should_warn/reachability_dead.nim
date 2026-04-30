## Reachability: dead state warning — Frozen has no incoming transitions
## from any initial state.
# expects: "Dead state 'Frozen'"
# expects: "Unreachable from any initial state"
import ../../src/typestates

type
  F = object
  Closed = distinct F
  Open = distinct F
  Frozen = distinct F

typestate F:
  consumeOnTransition = false
  states Closed, Open, Frozen
  initial:
    Closed
  transitions:
    Closed -> Open

proc op(f: Closed): Open {.transition.} =
  Open(F(f))

echo "reachability_dead compiled"
