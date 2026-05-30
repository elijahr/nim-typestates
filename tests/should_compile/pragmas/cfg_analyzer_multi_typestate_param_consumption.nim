## Test (Round-12 Gemini r11 finding #1, CFG-001 negative — multi-
## typestate-param consumption at call site): when a registered
## `{.transition.}` proc takes MULTIPLE sink-typed typestate-bearing
## parameters, the call-site per-arg consumption loop in
## `applyCallTransitions` must consume the tracked local at EVERY
## typestate-bearing argument position, not just the first match.
##
## Pre-round-12 the per-arg loop called `findRegisteredTransitionForArg`
## independently per argument, keying on `(callName, argStateType)`.
## For a call like `tx(f1, f2)` where `f1: T1` and `f2: T2`, the lookup
## found the transition via f1's source-state match but did not consume
## f2 — the transition's first-param sourceState was T1, not T2, so the
## per-arg name+source lookup for f2 returned `none`. f2 stayed in the
## live-set and false-fired CFG-001 at fall-through.
##
## Round-12 fix: `applyCallTransitions` resolves the full transition
## once via `findTransitionByCalleeAndArgStates` (the round-4/r5/r9
## helper that considers the full arg-state vector) and iterates the
## matched transition's `typestatedParams`, mapping each entry's
## `paramIndex` back to the call-site arg position and consuming (or
## advancing) the tracked local there.
import ../../../src/typestates

type
  Slot = object
    n: int

  Open = distinct Slot
  Pending = distinct Slot
  Closed = distinct Slot

typestate Slot:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Pending, Closed
  initial:
    Open
    Pending
  terminal:
    Closed
  transitions:
    Open -> Closed
    Pending -> Closed

proc combine(a: sink Open, b: sink Pending): Closed {.transition.} =
  ## Multi-typestate-param sink consumer: BOTH `a` and `b` are sink-typed
  ## typestate-bearing params. The registered transition's
  ## `typestatedParams` carries paramIndex=0 (Open, isSink=true) and
  ## paramIndex=1 (Pending, isSink=true). Round-14: explicit
  ## conversion-consume of `b` to its registered terminal Closed
  ## before constructing `result` (the sink-param pre-population skip
  ## that suppressed CFG-001 on `b` was reversed in round-14).
  discard Closed(b.Slot)
  result = Closed(a.Slot)

proc drive(a: var Open, b: var Pending): Closed {.transition.} =
  ## Both params are `var T` so round-2 pre-populates them into the
  ## live-set at proc entry: `a: Open`, `b: Pending`. The call
  ## `combine(a, b)`:
  ##   1. buildArgStatesFromCall → argStates=[some("Open"), some("Pending")]
  ##   2. findTransitionByCalleeAndArgStates matches `combine`'s single
  ##      registered overload (paramIndex=0/Open, paramIndex=1/Pending).
  ##   3. Per-typestatedParam loop consumes:
  ##      - paramIndex=0 (Open, isSink): drop `a` from tracking.
  ##      - paramIndex=1 (Pending, isSink): drop `b` from tracking.
  ##   4. Return result is the call's destination Closed — bound to the
  ##      proc's `result` via the transition's return type.
  ##
  ## Pre-round-12: step 3 consumed only `a` (the per-arg lookup matched
  ## via Open); `b` stayed Pending in the live-set. The fall-through
  ## return exit-edge then false-fired CFG-001 on `b`.
  result = combine(a, b)

verifyTypestates()
echo "cfg_analyzer_multi_typestate_param_consumption ok"
