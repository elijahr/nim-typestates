## Test (CFG-001 positive — round-3 #3 over-tracking regression check):
## `discard move(f)` must drop ONLY `f`, not unrelated tracked locals.
##
## Body: a registered transition proc declares two Open locals `f, g`.
## `discard move(f)` consumes f (round-3 #3 intrinsic-callee path). `g`
## is never moved/consumed. Fall-through must fire CFG-001 naming `g`.
##
## Confirms the intrinsic-callee special case in the discard handler is
## scoped to the underlying local the helper resolves, not a blanket
## live-set clear.
# expects: "has not reached a terminal state"
# expects: "g"
# expects: "Open"
# expects: "Closed"
import ../../../src/typestates

type
  Resource = object
    n: int

  Idle = distinct Resource
  Open = distinct Resource
  Closed = distinct Resource

typestate Resource:
  consumeOnTransition = false
  strictTransitions = false
  states Idle, Open, Closed
  initial:
    Idle
  terminal:
    Closed
  transitions:
    Idle -> Open
    Idle -> Closed
    Open -> Closed

proc primary(i: sink Idle): Closed {.transition.} =
  ## Body declares two Open locals; `discard move(f)` drops `f`. `g` is
  ## leaked at fall-through.
  var f {.used.}: Open
  var g {.used.}: Open
  discard move(f)
  result = Closed(i.Resource)

verifyTypestates()
