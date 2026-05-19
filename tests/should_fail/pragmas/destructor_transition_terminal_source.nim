## Test (DT-008): destructorTransition where the source state is already
## a terminal of the typestate (no transition possible).
## Expected error: "is already a terminal state"
# expects: "is already a terminal state"
import ../../../src/typestates

type
  Lifecycle = object
  Alive = distinct Lifecycle
  Dead = distinct Lifecycle

typestate Lifecycle:
  consumeOnTransition = false
  strictTransitions = false
  states Alive, Dead
  initial:
    Alive
  terminal:
    Dead
  transitions:
    Alive -> Dead

# Wrong: destructor on Dead, which is already terminal.
proc `=destroy`(d: var Dead) {.destructorTransition.} =
  discard
