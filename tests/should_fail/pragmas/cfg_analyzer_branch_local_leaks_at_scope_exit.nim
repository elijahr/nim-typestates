## Test (Round-4 Finding #1, CFG-001 positive — branch-local scope leak):
## a typestate-bearing local declared INSIDE one branch of an if (with
## an implicit else, i.e. an if-without-else), absent from the entry-set
## AND absent from at least one other branch, must reach a terminal
## state before the branch closes. Pre-round-4 the analyzer silently
## dropped these branch-locals from the merged live-set, escaping
## CFG-001 validation entirely. The fix validates terminal-reach (or a
## destructor) at branch-close.
##
## Pattern exercised inside a registered `{.transition.}` proc body:
##
##   proc work(q: sink Queued, cond: bool): Finished {.transition.} =
##     if cond:
##       var f: Open      # branch-local; not in entry, not in implicit-else
##       # branch closes WITHOUT consuming f to terminal
##     # implicit else: f is absent
##     # branch-close: f leaks. Round-4 -> CFG-001 at branch-close.
##     result = Finished(q.Job)
##
## Acceptance: the analyzer emits a CFG-001-style diagnostic naming the
## local and the current non-terminal state.
# expects: "has not reached a terminal state at this branch-close"
# expects: "Open"
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
  ## Branch-local `f` is declared inside the `if`, never consumed.
  ## The implicit else does not declare `f`, so `f` is absent from at
  ## least one branch — round-4 validation fires at branch-close.
  if cond:
    var f {.used.}: Open
  result = Finished(q.Job)

verifyTypestates()
