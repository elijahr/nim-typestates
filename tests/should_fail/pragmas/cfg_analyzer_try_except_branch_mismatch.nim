## Test (CFG-002 — try/except branch mismatch): try-body and an except
## branch each declare a typestate-bearing local with the SAME name but
## DIFFERENT non-terminal state types. Reconciliation at the post-try
## join must reject as inconsistent state across branches.
##
## Per §3.3 try/except: reconcile([bodyEnd, exceptEnd], hasElse=true). The
## reconciliation behaves identically to an if/else where each arm declares
## the local at a different non-terminal state.
# expects: "has inconsistent state across branches"
# expects: "Starting"
# expects: "Running"
import ../../../src/typestates

type
  Conduit = object
    n: int

  Idle = distinct Conduit
  Closed = distinct Conduit

typestate Conduit:
  consumeOnTransition = false
  strictTransitions = false
  states Idle, Closed
  initial:
    Idle
  terminal:
    Closed
  transitions:
    Idle -> Closed

type
  Job = object
    n: int

  Starting = distinct Job
  Running = distinct Job
  Done = distinct Job

typestate Job:
  consumeOnTransition = false
  strictTransitions = false
  states Starting, Running, Done
  initial:
    Starting
  terminal:
    Done
  transitions:
    Starting -> Running
    Running -> Done

proc shutdown(w: sink Idle): Closed {.transition.} =
  ## try-body declares `s: Starting`, except handler declares `s: Running`.
  ## Two non-terminal states at the merge: CFG-002 fires.
  try:
    var s {.used.}: Starting
  except CatchableError:
    var s {.used.}: Running
  result = Closed(w)

verifyTypestates()
