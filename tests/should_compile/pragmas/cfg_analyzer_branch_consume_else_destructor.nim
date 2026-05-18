## Test (Round-14 Gemini r13 MEDIUM — CFG-002 negative: branch
## reconciliation accepts non-consume tail when destructor covers
## the local). Pattern: a typestate-bearing local declared before
## an if-statement is consumed in one branch and left non-terminal
## in the implicit-else branch; the local's type has a registered
## `{.destructorTransition.}`. Nim's injected `=destroy` bridges the
## non-consume tail at scope-exit, so CFG-002 must NOT fire at the
## if-merge.
##
## Pre-round-14: CFG-002 false-fires because the consume-side
## reconciliation path emitted "inconsistent state across branches"
## without consulting `hasDestructorFor`. The branch-introduced-local
## path already short-circuits via the destructor (verify.nim lines
## 1417-1422); the entry-local consume-side reconciliation was the
## parallel gap closed in round-14.
##
## Post-round-14: clean. The destructor short-circuit at the
## reconciliation site drops the local from the merged live-set just
## as if every branch had consumed it.
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
  Bus = object
    handle: int

  Live = distinct Bus
  Dropped = distinct Bus

typestate Bus:
  consumeOnTransition = false
  strictTransitions = false
  states Live, Dropped
  initial:
    Live
  terminal:
    Dropped
  transitions:
    Live -> Dropped

proc `=destroy`(h: var Live) {.destructorTransition.} =
  ## Bridges Live -> Dropped at scope-exit. The non-consume branch of
  ## the if inside `work` relies on this destructor to bridge `c` at
  ## the if-merge.
  discard

proc close(c: sink Live): Dropped {.transition.} =
  ## Terminal-producing consumer of Live.
  result = Dropped(c.Bus)

proc work(q: sink Queued, cond: bool): Finished {.transition.} =
  ## `c` is declared BEFORE the if → present in the entry set of the
  ## reconcileBranches call. The consume-side branch advances `c` to
  ## terminal via `discard close(c)`; the implicit-else branch leaves
  ## it at `Live` (non-terminal). Pre-round-14 the reconciliation
  ## fired CFG-002 at the if-merge. Post-round-14 the destructor
  ## short-circuit drops `c` from the merged live-set, so the only
  ## non-terminal in scope after the merge is `q`, which is consumed
  ## by `result = Finished(q.Job)`.
  var c: Live
  if cond:
    discard close(c)
  result = Finished(q.Job)

verifyTypestates()
echo "cfg_analyzer_branch_consume_else_destructor ok"
