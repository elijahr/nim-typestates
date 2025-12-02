## Test that sealed typestates cannot be extended.
## This test should FAIL to compile - that's expected.

import ../../src/typestates

type
  Payment = object
  Created = distinct Payment
  Authorized = distinct Payment
  Hacked = distinct Payment

# First typestate - sealed by default
typestate Payment:
  states Created, Authorized
  transitions:
    Created -> Authorized

# This should cause a compile error: Payment is sealed
typestate Payment:
  states Hacked
  transitions:
    Authorized -> Hacked
