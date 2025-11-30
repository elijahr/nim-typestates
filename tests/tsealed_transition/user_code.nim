## This should FAIL to compile - external transition on sealed typestate

import payment
import ../../src/nim_typestates

# This should cause a compile error: Payment is sealed
proc bypass(p: Created): Authorized {.transition.} =
  result = Authorized(p.Payment)
