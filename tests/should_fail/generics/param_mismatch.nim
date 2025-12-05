## Test: Generic typestate with undeclared transition should fail
## Expected error: Undeclared transition
import ../../../src/typestates

type
  Box[T] = object
    value: T
  Empty[T] = distinct Box[T]
  Full[T] = distinct Box[T]
  Overflow[T] = distinct Box[T]  # Not in transitions

typestate Box[T]:
  strictTransitions = false
  states Empty[T], Full[T]
  transitions:
    Empty[T] -> Full[T]

# Wrong: Overflow is not a declared transition destination
proc overflow[T](b: Full[T]): Overflow[T] {.transition.} =
  Overflow[T](Box[T](b))
