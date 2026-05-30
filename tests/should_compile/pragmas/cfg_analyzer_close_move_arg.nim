## Test (CFG-001 negative — `close(move(f))` arg-shape, round-3 Finding #2):
## a registered transition called with its argument wrapped in `move(f)`
## (parens form, parsed as `nnkCall(move, f)`) must consume `f`.
##
## Pre-fix the per-arg pattern-matcher in `applyCallTransitions` only peeled
## `nnkCommand(move/sink, x)` (parens-less form `move f`); the `nnkCall`
## parens form `move(f)` fell through to the default `continue`, leaving
## `f` tracked at the caller. Idiomatic Nim consumers using
## `close(move(f))` to make the move explicit hit a false-positive CFG-001.
##
## Post-fix every arg-shape is routed through `extractTrackedLocal`, which
## unwraps `nnkCall(move, x)` symmetrically with `nnkCommand(move, x)`.
import ../../../src/typestates

type
  File = object
    n: int

  Open = distinct File
  Closed = distinct File

typestate File:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Closed

proc close(f: sink Open): Closed {.transition.} =
  result = Closed(f.File)

proc useMoveCall() {.notATransition.} =
  var f: Open
  discard close(move(f))
  # f consumed via close (sink); fall-through accepts.

verifyTypestates()
useMoveCall()
echo "cfg_analyzer_close_move_arg ok"
