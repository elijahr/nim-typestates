## Helper module for module_qualified_generic_source.nim.
## Defines a generic typestate whose states are then referenced from
## the test module as `typestate_generic_helper.StateA[T]` etc.
import ../../src/typestates

type
  Cell*[T] = object
    value*: T

  StateA*[T] = distinct Cell[T]
  StateB*[T] = distinct Cell[T]

typestate Cell[T]:
  consumeOnTransition = false
  strictTransitions = false
  states StateA[T], StateB[T]
  transitions:
    StateA -> StateB
