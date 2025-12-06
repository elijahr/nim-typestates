## Test: Bad arrow syntax should fail
## Expected error: parse error or "Expected '->'"
import ../../../src/typestates

type
  Broken = object
  A = distinct Broken
  B = distinct Broken

typestate Broken:
  consumeOnTransition = false  # Opt out for existing tests
  states A, B
  transitions:
    A <- B  # Wrong arrow direction
