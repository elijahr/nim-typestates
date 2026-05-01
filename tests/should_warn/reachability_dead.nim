## Reachability: dead state warning — Frozen has incoming edges (from Iso),
## but the only path INTO Frozen comes from Iso, which is itself unreachable
## from the initial Closed. So Frozen is reported as DEAD (reachable only
## from another unreachable state). Iso, which has no incoming edges and is
## not declared `initial:`, is reported as ORPHAN — see reachability_orphan.
# expects: "Dead state 'Frozen'"
# expects: "Unreachable from any initial state"
import ../../src/typestates

type
  F = object
  Closed = distinct F
  Open = distinct F
  Iso = distinct F
  Frozen = distinct F

typestate F:
  consumeOnTransition = false
  states Closed, Open, Iso, Frozen
  initial:
    Closed
  transitions:
    Closed -> Open
    Iso -> Frozen

proc op(f: Closed): Open {.transition.} =
  Open(F(f))

proc freeze(f: Iso): Frozen {.transition.} =
  Frozen(F(f))

echo "reachability_dead compiled"
