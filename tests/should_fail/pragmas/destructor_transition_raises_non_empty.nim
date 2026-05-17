## Test (DT-005): destructor with non-empty raises is rejected.
## Expected error: non-empty raises list, must be {.raises: [].}
# expects: "has non-empty raises list"
import ../../../src/typestates

type
  Buffer = object
    data: int
  Filled = distinct Buffer
  Drained = distinct Buffer

typestate Buffer:
  consumeOnTransition = false
  strictTransitions = false
  states Filled, Drained
  initial:
    Filled
  terminal:
    Drained
  transitions:
    Filled -> Drained

# Wrong: destructor declares raises: [IOError]; must be raises: [].
proc `=destroy`(b: var Filled) {.destructorTransition, raises: [IOError].} =
  discard
