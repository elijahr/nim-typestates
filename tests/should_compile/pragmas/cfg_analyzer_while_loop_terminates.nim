## Test (CFG-001 negative — while-loop reconciliation): a while loop's
## body declares a typestate-bearing local that reaches a terminal state.
## The loop-level reconcile([body-end, entry], hasElse=false) treats the
## local as scoped to the body (entry has no such local), so the merge
## drops it cleanly and the fall-through accepts.
##
## Per §3.3 loop handling: walk the body once; reconcile body-exit with
## entry. Locals scoped inside the body do not survive the join because
## they have no counterpart in the entry state.
import ../../../src/typestates

type
  Spool = object
    n: int

  Loaded = distinct Spool
  Empty = distinct Spool

typestate Spool:
  consumeOnTransition = false
  strictTransitions = false
  states Loaded, Empty
  initial:
    Loaded
  terminal:
    Empty
  transitions:
    Loaded -> Empty

proc drain(s: sink Loaded): Empty {.transition.} =
  ## while-body declares `t: Empty` (terminal) and discards. Each iteration
  ## creates a fresh body-local; nothing escapes the loop.
  var n = 3
  while n > 0:
    var t: Empty
    discard t
    dec n
  result = Empty(s)

verifyTypestates()
echo "cfg_analyzer_while_loop_terminates ok"
