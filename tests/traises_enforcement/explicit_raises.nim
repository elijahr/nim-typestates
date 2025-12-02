## Test that transition with explicit non-empty raises fails.
## This should FAIL to compile.

import ../../src/typestates

type
  File = object
  Closed = distinct File
  Open = distinct File

typestate File:
  states Closed, Open
  transitions:
    Closed -> Open

# This should fail: explicit raises with non-empty list
proc open(f: Closed): Open {.transition, raises: [IOError].} =
  result = Open(f)
