## Test (CFG-002 negative — case-reconciliation accepts agreement): all
## branches of a `case` statement declare the same typestate-bearing local
## at a terminal state. Reconciliation merges with `allSame == true` (or
## `allTerminal == true` when terminals differ); no diagnostic, fall-through
## exit edge accepts.
##
## Per §3.3: the `case` traversal mirrors `if` — each ofBranch (and the
## optional else) is walked with the entry LiveState, the per-branch
## end-states are collected into `reconcileBranches`.
import ../../../src/typestates

type
  Bus = object
    n: int

  Open = distinct Bus
  Sealed = distinct Bus

typestate Bus:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Sealed
  initial:
    Open
  terminal:
    Sealed
  transitions:
    Open -> Sealed

proc route(b: sink Open, n: int): Sealed {.transition.} =
  ## All three `of` arms plus the `else` declare `s: Sealed` (terminal).
  ## Reconciliation merges to the agreed terminal; no CFG-002.
  case n
  of 0:
    var s: Sealed
    discard s
  of 1:
    var s: Sealed
    discard s
  of 2:
    var s: Sealed
    discard s
  else:
    var s: Sealed
    discard s
  result = Sealed(b)

verifyTypestates()
echo "cfg_analyzer_case_all_branches_terminal ok"
