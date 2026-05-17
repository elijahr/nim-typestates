## Test (DT-010): two-arg destructorTransition where the spec SrcState
## does not match the destructor's parameter type (state-typed-param path).
## Expected error: "spec SrcState ... does not match destructor parameter type"
# expects: "spec SrcState"
# expects: "does not match destructor parameter type"
import ../../../src/typestates

type
  Door = object
  Locked = distinct Door
  Unlocked = distinct Door
  BrokenDoor = distinct Door

typestate Door:
  consumeOnTransition = false
  strictTransitions = false
  states Locked, Unlocked, BrokenDoor
  initial:
    Locked
  terminal:
    BrokenDoor
  transitions:
    Locked -> Unlocked
    Unlocked -> BrokenDoor
    Locked -> BrokenDoor

# Wrong: param is `var Locked` but spec claims source is `Unlocked`.
proc `=destroy`(d: var Locked) {.destructorTransition: Unlocked -> BrokenDoor.} =
  discard
