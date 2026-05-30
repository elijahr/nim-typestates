## Test (CFG-002 positive — Finding #2: inconsistent branch consumption):
## a typestate-bearing local declared BEFORE an if/else is consumed (via
## terminal discard) in one branch but left in a non-terminal state in
## the other. At the merge point, the analyzer must emit CFG-002 — pre-fix
## this case escaped detection because `reconcileBranches` silently
## dropped the local from tracking when one branch lacked it.
##
## Pattern exercised inside a registered transition proc body:
##
##   proc work(q: sink Queued): Finished {.transition.} =
##     var f: Open                # entry-set local
##     if cond:
##       discard close(f)         # consumes f to terminal (drops from set)
##     # else: f remains Open (non-terminal)
##     # merge here: inconsistent -> CFG-002.
##     result = Finished(q.Job)
##
## Note the `Open` local has no destructor, so the missing arm would
## otherwise escape via the silently-dropped path.
# expects: "has inconsistent state across branches"
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
  File = object
    h: int

  Open = distinct File
  Closed = distinct File

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
  result = Closed(f.File)

proc work(q: sink Queued, cond: bool): Finished {.transition.} =
  ## `f` is in the entry-set of the if; branch A consumes it via
  ## `discard close(f)` (Open -> Closed terminal, dropped); branch B
  ## does nothing -> f remains Open (non-terminal). Merge -> CFG-002.
  var f: Open
  if cond:
    discard close(f)
  result = Finished(q.Job)

verifyTypestates()
