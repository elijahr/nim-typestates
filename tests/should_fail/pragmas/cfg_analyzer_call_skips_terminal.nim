## Test (CFG-001 positive — call advances to non-terminal): a registered
## transition call advances a tracked local to a NON-terminal intermediate
## state. With no subsequent consumption of that local, the fall-through
## exit edge must still reject (CFG-001).
##
## Pattern exercised inside the body of a registered `{.transition.}`
## proc (the analyzer walks every registered proc body):
##
##   proc primary(q: sink Queued): Finished {.transition.} =
##     var k: Running                 # tracked Running (non-terminal, no destructor)
##     # no call to advance k to Finished
##     result = Finished(q.Job)
##     # fall-through: k is still Running -> CFG-001.
##
## Variation specifically exercising the call-tracking path: the body
## binds a local via `var k = startWork(seed)` (call-init form), where
## startWork's destination is Running (non-terminal). The analyzer's
## call/asgn handler must keep k tracked at Running so that the
## subsequent fall-through correctly flags it.
# expects: "has not reached a terminal state"
# expects: "Running"
# expects: "Finished"
import ../../../src/typestates

type
  Job = object
    n: int

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
    Queued -> Finished
    Running -> Finished

proc startWork(j: sink Queued): Running {.transition.} =
  ## Non-terminal destination.
  result = Running(j.Job)

proc primary(q: sink Queued): Finished {.transition.} =
  ## Body binds `k` via call-init to Running (non-terminal). No subsequent
  ## consumption of k -> CFG-001 at fall-through.
  var seed: Queued
  var k {.used.} = startWork(seed)
  result = Finished(q.Job)

verifyTypestates()
