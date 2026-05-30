## Test (CFG-001 negative — try/except, both arms reach terminal):
## a typestate-bearing local declared in the try body is consumed to a
## terminal state inside both the try-body trailing path AND each except
## branch's trailing path. Reconciliation at the post-try join sees all
## per-branch states agree (or are terminal), and the fall-through exit
## edge accepts.
##
## Per §3.3 try/except/finally handling: try body walked normally; each
## except branch walked with ENTRY state (pessimistic). The reconcile
## merges body-end + all except-ends. With both arms in terminal (and the
## except arm seeing the entry state without the local), the local from
## the body's perspective reaches terminal, and the join accepts.
import ../../../src/typestates

type
  Wire = object
    n: int

  Plugged = distinct Wire
  Unplugged = distinct Wire

typestate Wire:
  consumeOnTransition = false
  strictTransitions = false
  states Plugged, Unplugged
  initial:
    Plugged
  terminal:
    Unplugged
  transitions:
    Plugged -> Unplugged

proc shutdown(w: sink Plugged): Unplugged {.transition.} =
  ## try-body declares `s: Unplugged` (terminal); except handler does
  ## nothing typestate-bearing. Reconciliation accepts: the local from
  ## body-end is terminal, the except-end carries entry state (no local
  ## yet) so it contributes no constraint at the merge.
  try:
    var s: Unplugged
    discard s
  except CatchableError:
    discard
  result = Unplugged(w)

verifyTypestates()
echo "cfg_analyzer_try_except_terminal ok"
