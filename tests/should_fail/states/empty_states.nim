## Test: Empty states declaration should fail
## Expected error: something about states
import ../../../src/typestates

type Broken = object

typestate Broken:
  consumeOnTransition = false # Opt out for existing tests
  states # No states listed - should fail
  transitions:
    discard
