## Fixture for CLI warning capture: contains a dead state.
## Parsed by the CLI ast_parser; not compiled by the comprehensive runner.
import ../../src/typestates

type
  X = object
  A = distinct X
  B = distinct X
  Frozen = distinct X

typestate X:
  consumeOnTransition = false
  states A, B, Frozen
  initial:
    A
  transitions:
    A -> B

proc go(x: A): B {.transition.} =
  B(X(x))
