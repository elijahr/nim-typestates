## Test (CFG-002 — if-branch reconciliation): a typestate-bearing local
## named `s` is declared with DIFFERENT non-terminal state types in the two
## branches of an if/else. At the join point, `reconcileBranches` cannot
## merge: branch-A says s:Started, branch-B says s:Running. Neither is
## terminal, so the terminal-union exception does not apply. CFG-002 fires.
##
## Per §3.3 "branch reconciliation": "all branches must agree on the post-
## state of each typestated value... different state types across branches
## → reject as inconsistent state across branches".
# expects: "has inconsistent state across branches"
# expects: "Started"
# expects: "Running"
import ../../../src/typestates

type
  Slot = object
    n: int

  Idle = distinct Slot
  Closed = distinct Slot

typestate Slot:
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

  Started = distinct Job
  Running = distinct Job
  Done = distinct Job

typestate Job:
  consumeOnTransition = false
  strictTransitions = false
  states Started, Running, Done
  initial:
    Started
  terminal:
    Done
  transitions:
    Started -> Running
    Running -> Done

proc tick(s0: sink Idle, cond: bool): Closed {.transition.} =
  ## Both arms declare `s` with different non-terminal types. Reconciliation
  ## must emit CFG-002 at the join point.
  if cond:
    var s {.used.}: Started
  else:
    var s {.used.}: Running
  result = Closed(s0)

verifyTypestates()
