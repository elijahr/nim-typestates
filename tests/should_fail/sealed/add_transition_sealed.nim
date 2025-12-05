## Test: Adding transition to sealed typestate from external "module" should fail
## Note: This simulates external module by having transition defined after sealed typestate
## Expected error: "Cannot define transition on sealed typestate"
import ../../../src/typestates

type
  Payment = object
  Created = distinct Payment
  Captured = distinct Payment
  Refunded = distinct Payment  # External attempt

# Sealed by default
typestate Payment:
  states Created, Captured
  transitions:
    Created -> Captured

# Adding a new transition should fail since typestate is sealed
typestate Payment:
  states Refunded
  transitions:
    Captured -> Refunded
