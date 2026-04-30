## Fixture for CLI warning capture: contains a dead state (Frozen has
## incoming only from Iso, which is itself unreachable from initial A).
## Parsed by the CLI ast_parser; not compiled by the comprehensive runner.
import ../../src/typestates

type
  X = object
  A = distinct X
  B = distinct X
  Iso = distinct X
  Frozen = distinct X

typestate X:
  consumeOnTransition = false
  states A, B, Iso, Frozen
  initial:
    A
  transitions:
    A -> B
    Iso -> Frozen

proc go(x: A): B {.transition.} =
  B(X(x))
proc freeze(x: Iso): Frozen {.transition.} =
  Frozen(X(x))
