## Test (Round-9 Finding #1, CFG-001 negative — source-state-aware
## var-init lookup for trailing sink params): when a proc name is
## registered with multiple `{.transition.}` overloads sharing the same
## first-param source state but differing in the source state of a
## TRAILING `sink T` typestate-bearing param, the var-init binding
## (`var f = combine(arg0, arg1)`) must pick the overload whose
## trailing-param source state matches the actual source state of the
## call-site arg, so the LHS binds to the CORRECT destination.
##
## Pre-round-9 `extractTypestatedParams` matched ONLY `var T` params, so
## sink-T params at trailing positions were silently excluded from the
## per-proc `typestatedParams` seq. `findTransitionByCalleeAndArgStates`
## then had no constraint at the trailing position; both overloads
## matched on (name, position-0 source), and the last-registered won by
## countdown — mis-binding the LHS to the wrong destination. The
## downstream `close(f)` would not match (its source-state expectation
## diverged from f's actual tracked state), and `f` would leak as the
## wrong terminal-bearing state at fall-through — CFG-001 false fire.
##
## After round-9 `extractTypestatedParams` also captures `sink T` params
## (with `isSink=true`). The pre-population path skips `isSink=true`
## entries so transition bodies still verify cleanly, but the
## source-state-aware overload lookup uses ALL typestate-bearing param
## entries and correctly disambiguates by the trailing-param source
## state.
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

proc `=destroy`(x: var Stage1) {.destructorTransition.} =
  ## Destructor covers `helper: var Stage1` at fall-through. Stage1 is
  ## not consumed by `combine`'s call-site per-arg loop (the per-arg
  ## consumption keys on the first-param transition match; trailing
  ## sink params are not consumed by that path) — orthogonal to the
  ## round-9 OVERLOAD LOOKUP fix this fixture targets. The destructor
  ## bridges `helper` to terminal at fall-through so the test isolates
  ## the overload-lookup behavior without coupling to trailing-arg
  ## consumption.
  discard

proc combine(a: sink Open, b: sink Stage1): Mid1 {.transition.} =
  ## First overload: (Open, Stage1) -> Mid1. The TRAILING param's
  ## source state (`Stage1`) is the disambiguator round-9 targets.
  result = Mid1(a.Slot)

proc combine(a: sink Open, b: sink Stage2): Mid2 {.transition.} =
  ## Second overload (registered AFTER): (Open, Stage2) -> Mid2.
  ## Pre-round-9 the var-init lookup picks this last-registered
  ## overload via name-only countdown — `f` mis-binds as Mid2 even
  ## when the call-site trailing arg is Stage1.
  result = Mid2(a.Slot)

proc close(r: sink Mid1): Closed1 {.transition.} =
  ## Terminal-producing consumer of Mid1. Requires `f` tracked as Mid1.
  result = Closed1(r.Slot)

proc drive(seed: var Open, helper: var Stage1): Closed1 {.transition.} =
  ## Both params are `var T` so round-2 pre-populates them into the
  ## live-set at proc entry: `seed: Open`, `helper: Stage1`. The
  ## var-init `var f = combine(seed, helper)` then:
  ##   1. buildArgStatesFromCall sees seed=Open, helper=Stage1
  ##      -> argStates=[some("Open"), some("Stage1")]
  ##   2. applyCallTransitions drops seed AND helper (both sink-consumed)
  ##   3. tryBindLocalFromCallInit calls findTransitionByCalleeAndArgStates
  ##      Round-9 fix: paramIndex=1 typestatedParam now exists for the
  ##      sink-Stage1 param of the first overload (and sink-Stage2 for the
  ##      second). The lookup constrains argStates[1] == "Stage1" → only
  ##      the first overload matches → f binds as Mid1.
  ##   4. close(f) advances f to terminal Closed1.
  ##
  ## Pre-round-9: step 3 had no constraint at position 1; the countdown
  ## returned the (Open, Stage2)->Mid2 overload last-registered. `f`
  ## mis-bound as Mid2; `close(f)` would not match (close expects Mid1);
  ## `f` would leak as Mid2 at fall-through → CFG-001 false fire.
  var f = combine(seed, helper)
  result = close(f)

verifyTypestates()
echo "cfg_analyzer_overloaded_sink_transition_var_init ok"
