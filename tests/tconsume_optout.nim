## Test that consumeOnTransition = false allows copying.

import ../src/typestates

type
  File = object
    handle: int

  Closed = distinct File
  Open = distinct File

typestate File:
  consumeOnTransition = false # Opt out
  states Closed, Open
  transitions:
    Closed -> Open

proc open(f: Closed): Open {.transition.} =
  Open(File(handle: 1))

# This should work - copying is allowed
let closed = Closed(File(handle: 0))
let closed2 = closed # OK: copying allowed
echo "consumeOnTransition = false allows copying"
