## Test: Extending a sealed typestate should fail
## Expected error: "Cannot extend sealed typestate"
import ../../../src/typestates

type
  Locked = object
  StateA = distinct Locked
  StateB = distinct Locked
  StateC = distinct Locked # Trying to add

# Sealed by default
typestate Locked:
  consumeOnTransition = false # Opt out for existing tests
  states StateA, StateB
  transitions:
    StateA -> StateB

# This extension should fail
typestate Locked:
  consumeOnTransition = false # Opt out for existing tests
  states StateC
  transitions:
    StateB -> StateC
