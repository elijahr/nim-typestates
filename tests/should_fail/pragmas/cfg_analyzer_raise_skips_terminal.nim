## Test (CFG-001 — raise edge): a `raise` inside a registered transition
## proc creates an exit edge from any program point in the body. If a
## typestate-bearing local is in scope, non-terminal, and has no registered
## `{.destructorTransition.}` for its type, the analyzer must reject at the
## raise node.
##
## Per §3.3, raise is treated identically to return for exit-edge validation
## (CFG-001 unified for return + raise; the only difference is the `edgeKind`
## string in the diagnostic).
##
## We use a `Defect` (not tracked by `{.raises: [].}`) so the analyzer's
## CFG-001 fires BEFORE the raises checker. The transition pragma
## auto-injects `{.raises: [].}` — using a CatchableError would error at
## the raises checker first and the test would catch the wrong diagnostic.
##
## Here `tick(...)` is a {.transition.} proc whose body declares
## `s: Started` (non-terminal of typestate Job, no destructor). The raise on
## the conditional branch leaves `s` non-terminal -> CFG-001 fires.
# expects: "has not reached a terminal state at this raise"
# expects: "Started"
# expects: "Done"
import ../../../src/typestates

type
  Slot = object
    n: int

  Queued = distinct Slot
  Running = distinct Slot

typestate Slot:
  consumeOnTransition = false
  strictTransitions = false
  states Queued, Running
  initial:
    Queued
  terminal:
    Running
  transitions:
    Queued -> Running

type
  Job = object
    n: int

  Started = distinct Job
  Done = distinct Job

typestate Job:
  consumeOnTransition = false
  strictTransitions = false
  states Started, Done
  initial:
    Started
  terminal:
    Done
  transitions:
    Started -> Done

proc tick(q: sink Queued, fail: bool): Running {.transition.} =
  ## Body declares `s: Started`; on the `fail` branch the body raises a
  ## Defect (not tracked by `raises: []`). CFG-001 must fire on the raise
  ## edge: `s` is in `Started` (non-terminal) with no destructor.
  var s: Started
  if fail:
    raise newException(Defect, "boom") # CFG-001: 's' is Started, no destructor.
  result = Running(q)
  discard s

verifyTypestates()
