## Test (Round-4 Finding #3, CFG-001 negative — source-state-aware
## var-init lookup): when a proc name is registered with multiple
## `{.transition.}` overloads distinguished by source-state AND
## producing DIFFERENT destinations (e.g., `recover(Errored) -> Mid1`
## vs `recover(Locked) -> Mid2`), the var-init binding
## (`var f = recover(arg)`) must pick the overload whose source-state
## matches the actual source-state of the call-site arg, so the LHS
## binds to the CORRECT destination.
##
## Pre-round-4 the var-init lookup iterated `registeredProcs` by callee
## name only, so it picked the last-registered overload regardless of
## source-state. With two overloads producing different dests, picking
## the wrong one mis-binds `f` to a state that does NOT match the
## subsequent transition's expected source — so the downstream
## `close(f)` would not match in the analyzer (`f` was thought to be
## Mid2, not Mid1) and the analyzer would fire CFG-001 at the proc's
## fall-through edge.
##
## After round-4 the var-init binds `f` as Mid1 (correct), so the
## downstream `close(f)` advances `f` to terminal Closed1 and the
## fall-through accepts cleanly.
##
## The arg whose source-state must be observable to the analyzer is a
## `var T` parameter — round-2 pre-populates `var T` typestate-bearing
## params into the live-set at proc entry. Sink-typed args are NOT
## pre-populated (sink ownership transfers in, the value dies with the
## proc frame), so a sink arg would degrade `buildArgStatesFromCall` to
## `none` and the helper to name-only. The `var T` shape is the
## canonical site this round-4 fix targets.
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
    Errored -> Closed1

proc recover(r: sink Errored): Mid1 {.transition.} =
  ## First overload: Errored -> Mid1.
  result = Mid1(r.Resource)

proc recover(r: sink Locked): Mid2 {.transition.} =
  ## Second overload (registered AFTER): Locked -> Mid2. Pre-round-4
  ## the var-init lookup picks this last-registered overload (name-only
  ## countdown), mis-binding the LHS as Mid2 even when the call-site
  ## arg is Errored.
  result = Mid2(r.Resource)

proc close(r: sink Mid1): Closed1 {.transition.} =
  ## Terminal-producing consumer of Mid1. Requires `f` tracked as Mid1.
  result = Closed1(r.Resource)

proc drive(seed: var Errored): Closed1 {.transition.} =
  ## `seed: var Errored` is pre-populated by round-2 into the live-set
  ## at proc entry. The var-init `var f = recover(seed)` then:
  ##   1. buildArgStatesFromCall sees seed=Errored -> argStates=[some("Errored")]
  ##   2. applyCallTransitions advances/drops seed (sink-consume)
  ##   3. tryBindLocalFromCallInit calls findTransitionByCalleeAndArgStates
  ##      which picks recover(Errored): Mid1 (NOT recover(Locked): Mid2)
  ##   4. f binds as Mid1
  ## Then `close(f)` advances f to terminal Closed1; fall-through accepts.
  ##
  ## Pre-round-4: step 3 was a name-only countdown, picking recover(Locked).
  ## f would bind as Mid2; close(f) would not match (close expects Mid1),
  ## and f would leak as Mid2 at fall-through -> CFG-001.
  var f = recover(seed)
  result = close(f)

verifyTypestates()
echo "cfg_analyzer_overloaded_transition_var_init ok"
