## Test (CFG-001 positive — round-3 #3 over-tracking regression check):
## `discard move(f)` must drop ONLY `f`, not unrelated tracked locals.
##
## Body: a registered transition proc declares two Open locals `f, g`.
## `discard move(f)` consumes `f` (round-3 #3 intrinsic-callee path). `g`
## is never moved/consumed. Fall-through must fire CFG-001 naming `g`.
##
## Confirms the intrinsic-callee special case in the discard handler is
## scoped to the underlying local the helper resolves, not a blanket
## live-set clear.
##
## Round-5 Finding #3: `discard move(f)` is now CFG-003-checked against
## `f`'s pre-discard state; a non-terminal `f` with no destructor would
## fire CFG-003 BEFORE the fall-through CFG-001 we're testing for `g`.
## To isolate the CFG-001 intent, the Open state declares a registered
## `{.destructorTransition.}` so the `discard move(f)` clears CFG-003
## via the destructor short-circuit. `g` (Open) is still leaked at
## fall-through — but the destructor SHOULD also short-circuit `g`'s
## CFG-001 check, defeating the test. Instead we leave `g` at a state
## (Open) and have `f` at a SEPARATE typestate-bearing type that owns
## the destructor: then `discard move(f)` clears (destructor covers
## `f`'s type), while `g` (no destructor on Open) still triggers
## CFG-001 at fall-through.
# expects: "has not reached a terminal state"
# expects: "g"
# expects: "Open"
import ../../../src/typestates

type
  ResourceF = object
    n: int

  IdleF = distinct ResourceF
  OpenF = distinct ResourceF
  ClosedF = distinct ResourceF

typestate ResourceF:
  consumeOnTransition = false
  strictTransitions = false
  states IdleF, OpenF, ClosedF
  initial:
    IdleF
  terminal:
    ClosedF
  transitions:
    IdleF -> OpenF
    OpenF -> ClosedF

proc `=destroy`(x: var OpenF) {.destructorTransition.} =
  ## Bridges OpenF -> ClosedF; covers `f` so its `discard move(f)`
  ## clears CFG-003 via destructor short-circuit.
  discard

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
  ## Body declares `f` of `OpenF` (has destructor — `discard move(f)`
  ## clears CFG-003) and `g` of `Open` (no destructor — leaks at
  ## fall-through with CFG-001). `discard move(f)` must drop ONLY `f`,
  ## not `g`. Pre-round-3 fix: any move-discard would silently clear
  ## the live-set including `g`, suppressing the CFG-001 we expect.
  var f {.used.}: OpenF
  var g {.used.}: Open
  discard move(f)
  result = Closed(i.Resource)

verifyTypestates()
