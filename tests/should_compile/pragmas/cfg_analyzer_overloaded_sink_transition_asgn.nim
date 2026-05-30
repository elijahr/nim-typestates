## Test (Round-9 Finding #1, CFG-001 negative — source-state-aware asgn
## binding for trailing sink params): the asgn re-binding path
## (`f = combine(seed, helper)`) must use the same source-state-aware
## overload lookup as the var-init path. When overloads share the same
## first-param source state but differ in the source state of a TRAILING
## `sink T` typestate-bearing param, the asgn must pick the overload
## whose trailing-param source-state matches the call-site arg.
##
## Pre-round-9 the asgn lookup (via `findTransitionByCalleeAndArgStates`)
## had no constraint at trailing positions because
## `extractTypestatedParams` excluded sink params. The countdown picked
## the last-registered overload regardless of trailing-arg source state,
## mis-binding the LHS.
##
## After round-9 the asgn rebinds `f` as Mid1 (correct), so the
## downstream `close(f)` consumes `f` to terminal Closed1 cleanly.
##
## Round-12 (Gemini r11 finding #1) closed the orthogonal
## multi-typestate-param consumption gap in `applyCallTransitions`:
## per-arg consumption now iterates the matched transition's
## `typestatedParams` and consumes every sink-typed trailing arg.
## Stage1 (`helper`) is consumed by combine's call-site loop directly,
## so the round-9 `=destroy(x: var Stage1) {.destructorTransition.}`
## destructor that bridged `helper` to terminal at fall-through is no
## longer needed and was removed from this fixture as part of the
## round-12 patch.
##
## Round-14 (Gemini r13 HIGH) closed the sink-param pre-population
## skip in `runCfgAnalyzer`. Each `combine` overload's BODY now has
## its trailing `b: sink Stage1` (resp. Stage2) sink param tracked
## symmetrically with `a`. The bodies must explicitly consume `b`;
## an explicit conversion-consume `discard Closed1(b.Slot)` (resp.
## Closed2) routes `b` to its registered terminal via the same
## conversion-consume path that consumes `a` in the
## `result = Mid1(a.Slot)` expression. No destructor is needed; the
## call-site disambiguation in `drive` is unchanged.
import ../../../src/typestates

type
  Slot = object
    n: int

  Open = distinct Slot
  Stage1 = distinct Slot
  Stage2 = distinct Slot
  Mid1 = distinct Slot
  Mid2 = distinct Slot
  Closed1 = distinct Slot
  Closed2 = distinct Slot

typestate Slot:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Stage1, Stage2, Mid1, Mid2, Closed1, Closed2
  initial:
    Open
    Stage1
    Stage2
  terminal:
    Closed1
    Closed2
  transitions:
    Open -> Mid1
    Open -> Mid2
    Open -> Closed1
    Stage1 -> Closed1
    Stage2 -> Closed2
    Mid1 -> Closed1
    Mid2 -> Closed2

proc combine(a: sink Open, b: sink Stage1): Mid1 {.transition.} =
  ## First overload: (Open, Stage1) -> Mid1. Round-14: explicit
  ## conversion-consume of `b` to terminal Closed1 before
  ## constructing `result`.
  discard Closed1(b.Slot)
  result = Mid1(a.Slot)

proc combine(a: sink Open, b: sink Stage2): Mid2 {.transition.} =
  ## Second overload (registered AFTER): (Open, Stage2) -> Mid2.
  ## Pre-round-9 the asgn lookup picks this last-registered overload via
  ## name-only countdown — `f` mis-rebinds as Mid2 even when the
  ## call-site trailing arg is Stage1. Round-14: same explicit
  ## conversion-consume of `b` to terminal Closed2.
  discard Closed2(b.Slot)
  result = Mid2(a.Slot)

proc close(r: sink Mid1): Closed1 {.transition.} =
  ## Terminal-producing consumer of Mid1.
  result = Closed1(r.Slot)

proc drive(f: var Mid1, seed: var Open, helper: var Stage1): Closed1 {.transition.} =
  ## All three params are `var T` and pre-populated by round-2:
  ## `f: Mid1`, `seed: Open`, `helper: Stage1`. The asgn
  ## `f = combine(seed, helper)` is the round-9 target:
  ##   1. buildArgStatesFromCall sees seed=Open, helper=Stage1
  ##      -> argStates=[some("Open"), some("Stage1")]
  ##   2. applyCallTransitions drops seed AND helper (sink-consumed)
  ##   3. The asgn handler calls findTransitionByCalleeAndArgStates.
  ##      Round-9 fix: paramIndex=1 typestatedParam now exists for both
  ##      overloads (sink Stage1 vs sink Stage2). The lookup constrains
  ##      argStates[1] == "Stage1" → only the first overload matches →
  ##      f rebinds as Mid1.
  ##   4. close(f) advances f to terminal Closed1.
  ##
  ## Pre-round-9: step 3 had no constraint at position 1; countdown
  ## picked the (Open, Stage2)->Mid2 overload; `f` rebound as Mid2;
  ## `close(f)` would not match; `f` leaks as Mid2 → CFG-001.
  f = combine(seed, helper)
  result = close(f)

verifyTypestates()
echo "cfg_analyzer_overloaded_sink_transition_asgn ok"
