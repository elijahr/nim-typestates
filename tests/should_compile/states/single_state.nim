## Test: Typestate with single state compiles
import ../../../src/typestates

type
  Singleton = object
    value: int
  Only = distinct Singleton

typestate Singleton:
  isSealed = false
  strictTransitions = false
  states Only

# No transitions needed - single state

let s = Only(Singleton(value: 42))
doAssert Singleton(s).value == 42
echo "single_state test passed"
