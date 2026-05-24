## Test: non-identifier typestate section header
##
## A section header whose callee is not an identifier/symbol (here the
## parenthesized `(states)(Closed)`) must produce the clean
## `Unknown section in typestate block:` diagnostic, NOT an internal
## `node lacks field: strVal` compiler error from an unguarded `.strVal`.
##
## Discriminative: without the parser kind-guard this errors with
## `node lacks field: strVal` (an internal macro ICE); with the guard it
## errors with the clean user-facing message below.
# expects: "Unknown section in typestate block"
# rejects: "node lacks field: strVal"
import ../../../src/typestates

type
  File = object
  Closed = distinct File
  Open = distinct File

typestate File:
  consumeOnTransition = false # Opt out for existing tests
  states Closed, Open
  (states)(Closed):
    discard
