## Single-target match where the value source is a call expression.
## Verifies that the call expression evaluates EXACTLY ONCE (no duplication
## from macro expansion). A side-effect counter on `makeResolved()` is
## checked at the end to be `1` after a single `match makeResolved(): ...`.
import ../../../src/typestates

type
  Item = object
    n: int
  Pending = distinct Item
  Resolved = distinct Item

typestate Item:
  states Pending, Resolved
  transitions:
    Pending -> Resolved

proc resolve(p: sink Pending): Resolved {.transition.} =
  Resolved(Item(p))

var sideEffectCount = 0
proc makeResolved(): Resolved =
  inc sideEffectCount
  Pending(Item(n: 7)).resolve()

var captured = 0
match makeResolved():
  Resolved(r):
    captured = Item(r).n

doAssert sideEffectCount == 1,
  "value expression must evaluate exactly once; got " & $sideEffectCount
doAssert captured == 7
echo "match_single_target_call_expr test passed"
