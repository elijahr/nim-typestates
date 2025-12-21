## Test: Unknown section in typestate block
## Expected error: "Unknown section in typestate block"
import ../../../src/typestates

type
  Broken = object
  A = distinct Broken

typestate Broken:
  consumeOnTransition = false # Opt out for existing tests
  states A
  foobar:
    A -> A
