## Test (Round-4 Finding #2, CFG-001 negative — source-state-aware asgn
## binding): the asgn re-binding path (`f = recover(seed)`) must use
## the same source-state-aware overload lookup as the var-init path.
## When a proc name has multiple registered overloads producing
## different destinations, the asgn must pick the one whose source-
## state matches the call-site arg.
##
## Pre-round-4 the asgn lookup at verify.nim's nnkAsgn handler iterated
## `registeredProcs` by callee name only (last wins), mis-binding the
## LHS to the wrong destination when the wrong-source overload happened
## to be the last registered.
##
## After round-4 the asgn binds `f` as Mid1 (correct), so the
## downstream close consumes `f` to terminal Closed1.
##
## Pattern: `seed: var Errored` is pre-populated into the live-set by
## round-2 at proc entry. An entry-set local `f: Mid1` is declared
## with a `var` section that includes a Nim-level constructor binding.
## Then `f = recover(seed)` is the asgn-rebind round-4 targets.
import ../../../src/typestates

type
  Resource = object
    n: int

  Errored = distinct Resource
  Locked = distinct Resource
  Mid1 = distinct Resource
  Mid2 = distinct Resource
  Closed1 = distinct Resource
  Closed2 = distinct Resource

typestate Resource:
  consumeOnTransition = false
  strictTransitions = false
  states Errored, Locked, Mid1, Mid2, Closed1, Closed2
  initial:
    Errored
    Locked
  terminal:
    Closed1
    Closed2
  transitions:
    Errored -> Mid1
    Locked -> Mid2
    Mid1 -> Closed1
    Mid2 -> Closed2

proc recover(r: sink Errored): Mid1 {.transition.} =
  ## First overload: Errored -> Mid1.
  result = Mid1(r.Resource)

proc recover(r: sink Locked): Mid2 {.transition.} =
  ## Second overload (registered AFTER): Locked -> Mid2. Pre-round-4
  ## the asgn lookup picks this last-registered overload, mis-binding
  ## the LHS as Mid2.
  result = Mid2(r.Resource)

proc close(r: sink Mid1): Closed1 {.transition.} =
  ## Terminal-producing consumer of Mid1. Requires `f` tracked as Mid1.
  result = Closed1(r.Resource)

proc drive(f: var Mid1, seed: var Errored): Closed1 {.transition.} =
  ## Both params are `var T` so round-2 pre-populates them into the
  ## live-set at proc entry: `f: Mid1`, `seed: Errored`. The asgn
  ## `f = recover(seed)` is the round-4 target:
  ##   1. buildArgStatesFromCall sees seed=Errored -> argStates=[some("Errored")]
  ##   2. applyCallTransitions drops seed (sink-consume)
  ##   3. The asgn handler calls findTransitionByCalleeAndArgStates,
  ##      which picks recover(Errored): Mid1 (NOT recover(Locked): Mid2)
  ##   4. f rebinds as Mid1
  ## Then `close(f)` advances f to terminal Closed1; fall-through accepts.
  ##
  ## Pre-round-4: step 3 was a name-only countdown picking recover(Locked).
  ## f would rebind as Mid2; close(f) would not match (close expects Mid1),
  ## and f would leak as Mid2 -> CFG-001.
  f = recover(seed)
  result = close(f)

verifyTypestates()
echo "cfg_analyzer_overloaded_transition_asgn ok"
