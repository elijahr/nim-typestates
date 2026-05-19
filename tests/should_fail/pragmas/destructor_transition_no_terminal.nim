## Test (DT-007): destructorTransition on a typestate that declares no
## terminal states. The pragma rejects because destructors model terminal
## transitions and need at least one terminal.
## Expected error: "requires the typestate ... to declare at least one terminal state"
# expects: "to declare at least one terminal state"
import ../../../src/typestates

type
  Loop = object
  A = distinct Loop
  B = distinct Loop
  C = distinct Loop

# No `terminal:` block: typestate has no terminal states (the parser
# permits this even when the graph reaches dead-ends, as long as no
# transitions target the initial state).
typestate Loop:
  consumeOnTransition = false
  strictTransitions = false
  states A, B, C
  initial:
    A
  transitions:
    A -> B
    B -> C
    A -> C

proc `=destroy`(a: var A) {.destructorTransition.} =
  discard
