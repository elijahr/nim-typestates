import ../../src/typestates

type
  Payment* = object
    amount*: int
  Created* = distinct Payment
  Authorized* = distinct Payment

typestate Payment:
  # All typestates are sealed (no extension allowed)
  states Created, Authorized
  transitions:
    Created -> Authorized

proc authorize*(p: Created): Authorized {.transition.} =
  result = Authorized(p.Payment)
