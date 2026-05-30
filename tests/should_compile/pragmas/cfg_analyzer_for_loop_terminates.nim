## Test (CFG-001 negative — for-loop over a closed set): a for-loop's
## body declares a typestate-bearing local that reaches terminal each
## iteration. The loop-level reconcile drops the body-scoped local.
##
## Per §3.3 loop handling: for is handled identically to while —
## reconcile body-end with entry. The for-loop's iteration variable is
## not typestate-bearing (plain int) and does not interfere.
import ../../../src/typestates

type
  Bucket = object
    n: int

  Filled = distinct Bucket
  Drained = distinct Bucket

typestate Bucket:
  consumeOnTransition = false
  strictTransitions = false
  states Filled, Drained
  initial:
    Filled
  terminal:
    Drained
  transitions:
    Filled -> Drained

proc clear(b: sink Filled): Drained {.transition.} =
  for i in 0 .. 2:
    var t: Drained
    discard t
    discard i
  result = Drained(b)

verifyTypestates()
echo "cfg_analyzer_for_loop_terminates ok"
