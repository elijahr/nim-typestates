## Reachability: linear chain with initial+terminal — no warnings expected.
import ../../../src/typestates

type
  F = object
  Closed = distinct F
  Open = distinct F
  Errored = distinct F

typestate F:
  consumeOnTransition = false
  states Closed, Open, Errored
  initial:
    Closed
  terminal:
    Errored
  transitions:
    Closed -> Open
    Open -> Errored

proc op(f: Closed): Open {.transition.} =
  Open(F(f))
proc err(f: Open): Errored {.transition.} =
  Errored(F(f))

let c = Closed(F())
doAssert $c == "Closed"
echo "reachability_clean ok"
