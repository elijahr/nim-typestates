## Test: Duplicate transition declarations are deduplicated
import ../../../src/typestates

type
  Duped = object
  A = distinct Duped
  B = distinct Duped

typestate Duped:
  consumeOnTransition = false # Opt out for existing tests
  strictTransitions = false
  states A, B
  transitions:
    A -> B
    A -> B # Duplicate - should be silently ignored
    A -> B # Another duplicate

proc go(d: A): B {.transition.} =
  B(d.Duped)

let a = A(Duped())
let b = a.go()
echo "duplicate_transition test passed"
