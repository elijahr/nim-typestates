## Snippet: File typestate definition
## Used by docs for include-markdown

import ../../src/typestates

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
