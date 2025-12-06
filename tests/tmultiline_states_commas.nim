## Test inline state list with commas.
## Note: Nim's parser doesn't support commas in multiline blocks,
## so this tests the inline comma syntax which is still valid.

import ../src/typestates

type
  File = object
  Closed = distinct File
  Open = distinct File
  Errored = distinct File

typestate File:
  states Closed, Open, Errored
  transitions:
    Closed -> Open
    Open -> Closed
    Open -> Errored

proc open(f: Closed): Open {.transition.} =
  Open(File())

proc close(f: Open): Closed {.transition.} =
  Closed(File())

echo "Inline states with commas work!"
