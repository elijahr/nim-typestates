## Test (CFG-001 positive — round-3 #2 over-tracking regression check):
## consuming one local via `close(move(f))` must NOT silently drop an
## unrelated tracked local `g` that wasn't passed to any consume site.
## Confirms the round-3 unified `extractTrackedLocal` helper resolves
## only the specific arg-wrap target, not arbitrary nearby locals.
##
## Body: a registered transition proc declares two locals `f, g: Open`.
## `close(move(f))` consumes f. `g` is never consumed. Fall-through must
## fire CFG-001 naming `g`.
# expects: "has not reached a terminal state"
# expects: "g"
# expects: "Open"
# expects: "Closed"
import ../../../src/typestates

type
  Channel = object
    fd: int

  Idle = distinct Channel
  Open = distinct Channel
  Closed = distinct Channel

typestate Channel:
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

proc close(c: sink Open): Closed {.transition.} =
  result = Closed(c.Channel)

proc primary(i: sink Idle): Closed {.transition.} =
  ## Body declares two Open locals; only `f` is consumed via
  ## `close(move(f))`. `g` is leaked at fall-through.
  var f: Open
  var g {.used.}: Open
  discard close(move(f))
  result = Closed(i.Channel)

verifyTypestates()
