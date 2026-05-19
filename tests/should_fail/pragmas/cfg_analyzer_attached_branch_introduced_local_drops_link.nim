## Test (CFG-001 positive — §3.7 attached branch-introduced local
## survives a branch reconciliation, NO destructor): an attached
## holder local is declared INSIDE both branches of an if/else (not
## in the entry set), each branch leaves it in the initial state, and
## the merge propagates it into the post-join live-set via the
## second-pass branch-introduced path (line 1392). With NO
## `{.destructorTransition.}` registered against the holder, the
## fall-through edge must fire CFG-001 naming the attached local.
##
## Round-8 regression test (negative-case lock-in for the branch-
## introduced site). Pairs with
## `cfg_analyzer_attached_branch_introduced_local_destructor.nim` —
## together they validate that the attachedTypeName propagation
## through reconcileBranches's second-pass merge neither over-relaxes
## (this fixture must still fire) nor regresses destructor recognition
## (the paired fixture must compile clean).
# expects: "has not reached a terminal state"
# expects: "PortIdle"
# expects: "PortContext"
import ../../../src/typestates

type
  PortBase = object
    handle: int

  PortIdle = distinct PortBase
  PortReleased = distinct PortBase

typestate PortContext:
  consumeOnTransition = false
  strictTransitions = false
  states PortIdle, PortReleased
  initial:
    PortIdle
  terminal:
    PortReleased
  transitions:
    PortIdle -> PortReleased

# Attached holder type. NO destructor registered.
type PortHandle {.PortContext: PortIdle.} = object
  payload: int

proc routePort(src: sink PortIdle, cond: bool): PortReleased {.transition.} =
  ## `p` is declared INSIDE both branches — branch-introduced, not in
  ## entry set. Both branches leave it at PortIdle. reconcileBranches
  ## second pass (perBranch.len == effective.len, allSame) propagates
  ## it into the merged live-set. Round-8 fix preserves
  ## `attachedTypeName=PortHandle` through the merge. With no
  ## destructor registered the fall-through edge fires CFG-001
  ## naming `p`.
  if cond:
    var p {.used.}: PortHandle
  else:
    var p {.used.}: PortHandle
  result = PortReleased(src.PortBase)

verifyTypestates()
