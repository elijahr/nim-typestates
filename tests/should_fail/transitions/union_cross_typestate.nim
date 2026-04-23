## Test: Union sources that span two different typestates must fail.
##
## Source X belongs to typestate TS1 while source Y belongs to typestate
## TS2; the diagnostic must explain that union sources must share a
## typestate.
# expects: "must share a typestate"
import ../../../src/typestates

type
  TS1 = object
    a: int

  TS2 = object
    b: int

  X = distinct TS1
  Z = distinct TS1
  Y = distinct TS2

typestate TS1:
  consumeOnTransition = false
  strictTransitions = false
  states X, Z
  transitions:
    X -> Z

typestate TS2:
  consumeOnTransition = false
  strictTransitions = false
  states Y

proc mix(v: X | Y): Z {.transition.} =
  Z(TS1(v))
