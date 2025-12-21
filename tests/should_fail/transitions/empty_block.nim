## Test: Empty transitions block should fail
## Expected error: "transitions block is empty"
import ../../../src/typestates

type
  Broken = object
  A = distinct Broken
  B = distinct Broken

typestate Broken:
  consumeOnTransition = false # Opt out for existing tests
  states A, B
  transitions:
    discard # Empty - should fail or at minimum do nothing useful
