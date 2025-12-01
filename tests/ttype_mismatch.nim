## Test demonstrating that Nim's type checker catches return type mismatches.
##
## This test shows that even though the {.transition.} pragma validates the
## transition is declared, Nim's type system catches the actual type mismatch
## if the implementation returns the wrong type.
##
## This is a compile-fail test.

import nim_typestates

type
  File = object
    path: string
  Closed = distinct File
  Open = distinct File

typestate File:
  states Closed, Open
  transitions:
    Closed -> Open
    Open -> Closed

# This proc declares the correct transition (Closed -> Open)
# but returns the wrong type (Closed instead of Open)
# The transition pragma passes, but Nim's type checker catches the error
proc open(f: Closed, path: string): Open {.transition.} =
  result = Closed(f)  # Wrong! Returns Closed, not Open
