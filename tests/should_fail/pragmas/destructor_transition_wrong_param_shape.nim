## Test (DT-004): destructor where param is NOT `var T` (e.g., bare T).
## Expected error: "must take its parameter by `var`"
# expects: "must take its parameter by `var`"
import ../../../src/typestates

type
  Bag = object
  Sealed = distinct Bag
  Opened = distinct Bag

typestate Bag:
  consumeOnTransition = false
  strictTransitions = false
  states Sealed, Opened
  initial:
    Sealed
  terminal:
    Opened
  transitions:
    Sealed -> Opened

# Wrong: missing `var` modifier on parameter.
proc `=destroy`(s: Sealed) {.destructorTransition.} =
  discard
