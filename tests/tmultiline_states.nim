## Test multiline state list syntax.

import ../src/typestates

type
  File = object
  Closed = distinct File
  Open = distinct File
  Errored = distinct File

typestate File:
  states:
    Closed
    Open
    Errored
  transitions:
    Closed -> Open
    Open -> Closed
    Open -> Errored

proc open(f: Closed): Open {.transition.} =
  Open(File())

proc close(f: Open): Closed {.transition.} =
  Closed(File())

echo "Multiline states work!"
