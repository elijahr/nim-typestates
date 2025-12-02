# This test should FAIL to compile - that's the expected behavior

import ../../src/typestates

type
  File = object
  Closed = distinct File
  Open = distinct File
  Locked = distinct File  # Not in typestate

typestate File:
  states Closed, Open
  transitions:
    Closed -> Open
    Open -> Closed

# This should cause a compile error: Locked is not a valid state
proc lock(f: Open): Locked {.transition.} =
  result = Locked(f)
