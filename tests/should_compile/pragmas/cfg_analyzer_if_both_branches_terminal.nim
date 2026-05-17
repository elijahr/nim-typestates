## Test (CFG-002 negative — if-reconciliation accepts agreement): both
## branches of an if/else declare the same typestate-bearing local at the
## SAME terminal state. `reconcileBranches` merges with `allSame == true`
## and emits no diagnostic; the fall-through validateExitEdge then accepts
## the local because its state is terminal.
##
## Per §3.3 "branch reconciliation": when all branches agree on a local's
## state at the join, the merge succeeds. When that agreed state is also
## terminal, downstream exit edges (here: fall-through implicit return)
## accept without further work.
import ../../../src/typestates

type
  Channel = object
    n: int

  Idle = distinct Channel
  Closed = distinct Channel

typestate Channel:
  consumeOnTransition = false
  strictTransitions = false
  states Idle, Closed
  initial:
    Idle
  terminal:
    Closed
  transitions:
    Idle -> Closed

proc emit(c: sink Idle, fast: bool): Closed {.transition.} =
  ## Both arms of the if/else declare `s: Closed` (terminal). Reconciliation
  ## sees the same state on both branches, merges cleanly, no CFG-002.
  if fast:
    var s: Closed
    discard s
  else:
    var s: Closed
    discard s
  result = Closed(c)

verifyTypestates()
echo "cfg_analyzer_if_both_branches_terminal ok"
