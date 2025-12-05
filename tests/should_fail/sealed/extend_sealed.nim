## Test: Extending a sealed typestate should fail
## Expected error: "Cannot extend sealed typestate"
import ../../../src/typestates

type
  Locked = object
  StateA = distinct Locked
  StateB = distinct Locked
  StateC = distinct Locked  # Trying to add

# Sealed by default
typestate Locked:
  states StateA, StateB
  transitions:
    StateA -> StateB

# This extension should fail
typestate Locked:
  states StateC
  transitions:
    StateB -> StateC
