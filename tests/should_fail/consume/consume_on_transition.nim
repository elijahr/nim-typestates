## Test that consumeOnTransition prevents reusing old state.

import ../../../src/typestates

type
  File = object
    handle: int
  Closed = distinct File
  Open = distinct File

typestate File:
  # consumeOnTransition = true is the default
  states Closed, Open
  transitions:
    Closed -> Open
    Open -> Closed

proc open(f: Closed): Open {.transition.} =
  Open(File(handle: 1))

proc close(f: Open): Closed {.transition.} =
  Closed(File(handle: 0))

# This should FAIL to compile - trying to copy a state
let closed = Closed(File(handle: 0))
let closed2 = closed  # ERROR: cannot copy
