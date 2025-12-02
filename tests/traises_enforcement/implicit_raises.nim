## Test that transition calling raising proc fails.
## This should FAIL to compile because the transition macro adds raises: []
## and the compiler will catch that readFile can raise.

import ../../src/typestates
import std/os

type
  Document = object
    content: string
  Empty = distinct Document
  Loaded = distinct Document

typestate Document:
  states Empty, Loaded
  transitions:
    Empty -> Loaded

# This should fail: readFile raises IOError, but we've enforced raises: []
proc load(d: Empty, path: string): Loaded {.transition.} =
  result = Loaded(d)
  result.Document.content = readFile(path)  # raises IOError!
