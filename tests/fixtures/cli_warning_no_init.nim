## Fixture: no initial:/terminal: blocks, so the reachability analyzer
## must NOT fire and produce no warnings about dead states.
import ../../src/typestates

type
  Y = object
  P = distinct Y
  Q = distinct Y
  R = distinct Y

typestate Y:
  consumeOnTransition = false
  states P, Q, R
  transitions:
    P -> Q

proc go(y: P): Q {.transition.} =
  Q(Y(y))
