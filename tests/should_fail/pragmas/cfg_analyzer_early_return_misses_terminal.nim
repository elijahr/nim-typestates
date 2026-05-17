## Test (CFG-001): early return inside a registered transition proc leaves
## a typestate-bearing local in a non-terminal state with no registered
## destructor. The CFG analyzer must reject at the return edge.
##
## The local `s: Started` is in `Started` (non-terminal of typestate Task)
## when the early-return branch fires. No `{.destructorTransition.}` is
## registered for `Started`, so the analyzer cannot recover via destructor
## injection — CFG-001 fires on the `return` node.
# expects: "has not reached a terminal state at this return"
# expects: "Started"
# expects: "Done"
import ../../../src/typestates

type
  Job = object
    id: int

  Queued = distinct Job
  Running = distinct Job
  Finished = distinct Job

typestate Job:
  consumeOnTransition = false
  strictTransitions = false
  states Queued, Running, Finished
  initial:
    Queued
  terminal:
    Finished
  transitions:
    Queued -> Running
    Running -> Finished

type
  Task = object
    n: int

  Started = distinct Task
  Done = distinct Task

typestate Task:
  consumeOnTransition = false
  strictTransitions = false
  states Started, Done
  initial:
    Started
  terminal:
    Done
  transitions:
    Started -> Done

proc tick(q: sink Queued, skip: bool): Running {.transition.} =
  ## Registered transition. Body declares `s: Started`, which is
  ## non-terminal in typestate `Task` and has no destructor — CFG-001
  ## must fire on the early `return`.
  var s: Started
  if skip:
    result = Running(q)
    return # CFG-001 on this return: 's' is Started, no destructor.
  result = Running(q)
  discard s

verifyTypestates()
