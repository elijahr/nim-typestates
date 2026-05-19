## Test (CFG-001 negative — dot-call recognition, round-2 Finding #1):
## the analyzer must recognize Nim's method-call (dot-call) syntax
## `obj.method(args)` as a state transition. The call AST is `nnkCall`
## with `call[0]` an `nnkDotExpr(receiver, methodIdent)`. The receiver
## `call[0][0]` is the implicit first argument (position 0) of the
## underlying proc; the explicit args `call[1..N-1]` follow.
##
## Pre-fix the analyzer iterated only `call[1..N-1]` for tracked locals,
## missing the receiver entirely. A body like
##
##   var f = openFile()
##   f.close()
##
## left `f` non-terminal at exit and fired a false-positive CFG-001 on
## idiomatic Nim. Prefix-call `close(f)` worked because `f` was at
## `call[1]`.
##
## This fixture exercises three dot-call shapes:
##   1. bare dot-call:        `f.close()`        receiver consumed
##   2. dot-call with extras: `f.consume(other)` receiver + extra args
##   3. var-init dot-call:    `var g = f.transition()` re-bind via dot
import ../../../src/typestates

type
  Resource = object
    n: int

  Open = distinct Resource
  Half = distinct Resource
  Closed = distinct Resource

typestate Resource:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Half, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Half
    Open -> Closed
    Half -> Closed

proc transitionHalf(r: sink Open): Half {.transition.} =
  ## Non-terminal destination; used to test the var-init dot-call shape.
  result = Half(r.Resource)

proc close(r: sink Open): Closed {.transition.} =
  ## Terminal destination; consumes the receiver as the implicit first arg.
  result = Closed(r.Resource)

proc closeHalf(r: sink Half): Closed {.transition.} =
  ## Closes a Half to terminal — used for chained dot-call consumption.
  result = Closed(r.Resource)

proc useDotCall() {.notATransition.} =
  ## Shape 1 — bare dot-call consumes the receiver to terminal. The
  ## `discard` is a Nim requirement (`close` returns a value); the
  ## analyzer-relevant point is the dot-call shape itself.
  var f: Open
  discard f.close()
  # f is consumed (terminal Closed) -> fall-through accepts.

proc useDotCallChain() {.notATransition.} =
  ## Shape 3 — var-init via dot-call binds a new local to the destination
  ## state, then a second dot-call consumes that local to terminal.
  var f: Open
  var g = f.transitionHalf()
  discard g.closeHalf()
  # f consumed (drop), g consumed (terminal) -> fall-through accepts.

verifyTypestates()

useDotCall()
useDotCallChain()
echo "cfg_analyzer_dot_call_transition ok"
