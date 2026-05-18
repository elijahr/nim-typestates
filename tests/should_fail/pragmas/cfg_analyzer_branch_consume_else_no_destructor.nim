## Test (Round-14 Gemini r13 MEDIUM — CFG-002 positive regression
## guard: destructor short-circuit MUST NOT mask the case where the
## local's type has NO registered destructor). Without a
## `{.destructorTransition.}` for `Live`, the non-consume branch's
## tail leaks the local; CFG-002 must still fire at the if-merge.
##
## This is the negative companion to
## `cfg_analyzer_branch_consume_else_destructor.nim` — it locks in
## the destructor-guarded path as a NARROW relaxation of CFG-002,
## not a blanket suppression. Pre- and post-round-14 both fire; the
## fixture exists to prevent a future regression that over-broadens
## the short-circuit (e.g., dropping the local unconditionally).
# expects: "has inconsistent state across branches"
# expects: "Live"
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

# Intentionally NO `{.destructorTransition.}` for Live. The non-consume
# branch's tail in `work` has no scope-exit bridge — CFG-002 must fire.

proc close(c: sink Live): Dropped {.transition.} =
  ## Terminal-producing consumer of Live.
  result = Dropped(c.Bus)

proc work(q: sink Queued, cond: bool): Finished {.transition.} =
  ## `c` is in the entry set of the if. Consume branch drops it to
  ## terminal; else branch leaves it at `Live`. No destructor →
  ## CFG-002 fires at the if-merge.
  var c: Live
  if cond:
    discard close(c)
  result = Finished(q.Job)

verifyTypestates()
