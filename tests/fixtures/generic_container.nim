## Fixture: Generic Container typestate
import ../../src/typestates

type
  Container*[T] = object
    items*: seq[T]
  Empty*[T] = distinct Container[T]
  HasItems*[T] = distinct Container[T]
  Full*[T] = distinct Container[T]

typestate Container[T]:
  isSealed = false
  strictTransitions = false
  states Empty[T], HasItems[T], Full[T]
  transitions:
    Empty[T] -> HasItems[T]
    HasItems[T] -> Full[T]
    HasItems[T] -> Empty[T]
    Full[T] -> HasItems[T]
