## Test (Round-4 Finding #1, CFG-001 negative — branch-local consumed
## within its branch): a typestate-bearing local declared inside one
## branch IS allowed when the same branch consumes it via a registered
## transition call before branch-close. Validates the round-4 fix does
## not over-fire: branch-locals that DO reach terminal inside their
## declaring branch compile cleanly.
##
## Pattern exercised inside a registered `{.transition.}` proc body:
##
##   if cond:
##     var f: Open
##     discard close(f)    # f consumed inside branch
##   # branch-close: f is terminal in the one branch, absent from else.
##   # Round-4 -> clean (terminal short-circuit).
import ../../../src/typestates

type
  Job = object
    n: int

  Queued = distinct Job
  Finished = distinct Job

typestate Job:
  consumeOnTransition = false
  strictTransitions = false
  states Queued, Finished
  initial:
    Queued
  terminal:
    Finished
  transitions:
    Queued -> Finished

type
  FileObj = object
    h: int

  Open = distinct FileObj
  Closed = distinct FileObj

typestate FileCtx:
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
  ## Registered transition consuming Open, producing terminal Closed.
  result = Closed(f.FileObj)

proc work(q: sink Queued, cond: bool): Finished {.transition.} =
  ## Branch-local `f` is consumed via `discard close(f)` before the
  ## branch closes. The else arm doesn't declare `f`. The terminal
  ## short-circuit in round-4 branch-close validation accepts this.
  if cond:
    var f: Open
    discard close(f)
  result = Finished(q.Job)

verifyTypestates()
echo "cfg_analyzer_branch_local_consumed_in_branch ok"
