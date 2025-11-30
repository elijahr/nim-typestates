import ../../src/nim_typestates

type
  Payment* = object
    amount*: int
  Created* = distinct Payment
  Authorized* = distinct Payment

typestate Payment:
  # isSealed = true (default)
  states Created, Authorized
  transitions:
    Created -> Authorized

proc authorize*(p: Created): Authorized {.transition.} =
  result = Authorized(p.Payment)
