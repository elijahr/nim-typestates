## Test (Round-12 Gemini r11 finding #1, CFG-001 negative — multi-
## typestate-param consumption composes with source-state-aware
## overload disambiguation): two registered transitions share the
## same name and first-param source-state, differing only in the
## TRAILING typestate-bearing param's source-state. The call-site
## arg-state vector picks one overload, and the round-12 per-arg
## consumption loop must consume ALL typestate-bearing args according
## to the MATCHED overload's `typestatedParams` — not whichever
## name-only first-match the pre-round-12 per-arg loop happened on.
##
## Pre-round-12 the per-arg loop matched independently per argument
## using `findRegisteredTransitionForArg` (which keys on name +
## first-param sourceState). For a call site with two registered
## overloads `(Open, OpenSecondary) -> ClosedA` and
## `(Open, OpenTertiary) -> ClosedB`, the per-arg lookup for the
## first arg matched whichever overload's first-param state was Open
## (either one). The trailing-arg's per-arg lookup keyed on the
## TRAILING arg's state (OpenSecondary or OpenTertiary), and since
## the overload's first-param sourceState was Open (not OpenSecondary
## or OpenTertiary), the trailing-arg lookup returned `none` — the
## trailing arg was NOT consumed. Round-12 fixes both by resolving
## the full transition once via `findTransitionByCalleeAndArgStates`
## and consuming each `typestatedParam`-mapped arg position.
import ../../../src/typestates

type
  Slot = object
    n: int

  Open = distinct Slot
  OpenSecondary = distinct Slot
  OpenTertiary = distinct Slot
  ClosedA = distinct Slot
  ClosedB = distinct Slot

typestate SlotContext:
  consumeOnTransition = false
  strictTransitions = false
  states Open, OpenSecondary, OpenTertiary, ClosedA, ClosedB
  initial:
    Open
    OpenSecondary
    OpenTertiary
  terminal:
    ClosedA
    ClosedB
  transitions:
    Open -> ClosedA
    Open -> ClosedB
    OpenSecondary -> ClosedA
    OpenTertiary -> ClosedB

proc combine(a: sink Open, b: sink OpenSecondary): ClosedA {.transition.} =
  ## First overload: (Open, OpenSecondary) -> ClosedA. Round-14:
  ## explicit conversion-consume of `b` to its registered terminal
  ## ClosedA before constructing `result` (pre-round-14 the
  ## sink-param pre-population skip suppressed CFG-001 on `b`).
  discard ClosedA(b.Slot)
  result = ClosedA(a.Slot)

proc combine(a: sink Open, b: sink OpenTertiary): ClosedB {.transition.} =
  ## Second overload (registered AFTER): (Open, OpenTertiary) -> ClosedB.
  ## Round-14: same explicit conversion-consume of `b` to terminal
  ## ClosedB.
  discard ClosedB(b.Slot)
  result = ClosedB(a.Slot)

proc driveA(a: var Open, b: var OpenSecondary): ClosedA {.transition.} =
  ## Call `combine(a, b)` with argStates=[Open, OpenSecondary]. The
  ## round-12 fix:
  ##   1. findTransitionByCalleeAndArgStates picks the first overload
  ##      (paramIndex=1 typestatedParam state=OpenSecondary matches).
  ##   2. Per-typestatedParam loop consumes BOTH `a` and `b` via the
  ##      first overload's typestatedParams.
  ##   3. LHS binds as ClosedA via tryBindLocalFromCallInit.
  result = combine(a, b)

proc driveB(a: var Open, b: var OpenTertiary): ClosedB {.transition.} =
  ## Call `combine(a, b)` with argStates=[Open, OpenTertiary]. The
  ## lookup picks the second overload (paramIndex=1 typestatedParam
  ## state=OpenTertiary matches). Both args consumed. LHS binds as
  ## ClosedB.
  result = combine(a, b)

verifyTypestates()
echo "cfg_analyzer_multi_typestate_param_overloaded ok"
