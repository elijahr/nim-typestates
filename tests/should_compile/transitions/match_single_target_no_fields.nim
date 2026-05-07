## Single-target match on a state declared from an empty (no-field) object.
## Verifies that `let bind = move(value)` works on the empty distinct even
## when the bound value is just discarded (or lightly inspected).
import ../../../src/typestates

type
  Marker = object
  Started = distinct Marker
  Done = distinct Marker

typestate Marker:
  states Started, Done
  transitions:
    Started -> Done

proc finish(s: sink Started): Done {.transition.} =
  Done(Marker())

var d = Started(Marker()).finish()
var seen = false
match d:
  Done(x):
    discard x
    seen = true
doAssert seen
echo "match_single_target_no_fields test passed"
