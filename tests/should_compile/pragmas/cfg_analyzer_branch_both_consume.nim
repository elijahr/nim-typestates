## Test (Round-14 Gemini r13 MEDIUM — CFG-002 negative regression
## guard: when BOTH branches consume the entry-set local, the merge
## point is clean regardless of destructor coverage). This is the
## baseline-clean case the round-14 destructor short-circuit must
## continue to honor without re-introducing CFG-002 (a guard against
## over-eager regression in the reconciliation logic).
##
## Pre-round-14: clean (both branches absent from the merged live-set;
## `presentStates.len == 0` exits early).
## Post-round-14: clean (same path; destructor check is unreachable
## because `anyPresentNonTerminal` is false).
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

proc close(c: sink Live): Dropped {.transition.} =
  ## Terminal-producing consumer of Live.
  result = Dropped(c.Bus)

proc work(q: sink Queued, cond: bool): Finished {.transition.} =
  ## Both branches advance `c` to terminal via `close(c)`. At the
  ## if-merge `c` is absent from every effective branch
  ## (`presentStates.len == 0`); reconciliation drops it cleanly.
  ## No destructor needed; CFG-002 path is never entered.
  var c: Live
  if cond:
    discard close(c)
  else:
    discard close(c)
  result = Finished(q.Job)

verifyTypestates()
echo "cfg_analyzer_branch_both_consume ok"
