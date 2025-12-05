## Test: Unknown section in typestate block
## Expected error: "Unknown section in typestate block"
import ../../../src/typestates

type
  Broken = object
  A = distinct Broken

typestate Broken:
  states A
  foobar:  # Unknown section
    A -> A
