## Fixture: Basic File typestate for testing
import ../../src/typestates

type
  File* = object
    path*: string
    fd*: int
  Closed* = distinct File
  Open* = distinct File
  Reading* = distinct File
  Writing* = distinct File

typestate File:
  strictTransitions = false
  states Closed, Open, Reading, Writing
  transitions:
    Closed -> Open
    Open -> Closed
    Open -> Reading
    Open -> Writing
    Reading -> Open
    Writing -> Open
    * -> Closed
