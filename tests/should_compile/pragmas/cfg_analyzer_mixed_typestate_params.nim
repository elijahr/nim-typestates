## Test (Round-5 Finding #1, CFG-001 negative — mixed typestate /
## non-typestate parameters do not mis-reject in
## `findTransitionByCalleeAndArgStates`): a registered transition proc
## that mixes typestate-bearing `var T` parameters with non-typestate
## parameters (e.g. `int`) at intervening positions must be matchable by
## the source-state-aware overload lookup.
##
## Pre-round-5 (regression introduced in round-4):
## `findTransitionByCalleeAndArgStates` iterated `argStates` (one entry
## per call-site arg position) and indexed into `p.typestatedParams`
## (one entry per typestate-bearing param, compacted) with the SAME
## index `j`. When the proc interleaved a non-typestate param between
## typestate-bearing ones, the trailing typestate-bearing arg's call-
## site position was beyond `typestatedParams.len`, tripping the OOB
## guard and falsely rejecting the proc.
##
## Post-round-5: `TypestatedParam` captures `paramIndex` (each entry's
## 0-based proc-parameter position), and the lookup iterates the
## compacted `typestatedParams` seq, indexing into `argStates` via
## `paramIndex`. The mixed-shape proc resolves cleanly.
##
## The arg whose source-state must be observable is a `var T` param
## (round-2 pre-populates `var T` typestate-bearing params at proc
## entry; sink/value-typed params do NOT enter `typestatedParams`).
## We give `mt` a `sink Open` at position 0 (the macro requires
## first-param state-typing; sink takes ownership), an `int` at
## position 1 (non-typestate), and a `var Open` at position 2 (the
## typestate-bearing trailing param that pre-round-5 was unreachable
## via the OOB-guarded lookup). The var-init caller binds `f` from
## `mt(a, 5, b)` where `a` and `b` are both Open-typed locals; the
## lookup must align call-site position 2 with
## `typestatedParams[0].paramIndex == 2` (after the position-0
## sourceState check folded `a`'s constraint into the first-param
## check), NOT `typestatedParams[2]` (out-of-bounds, pre-round-5
## rejection).
import ../../../src/typestates

type
  Pipeline = object
    step: int

  Open = distinct Pipeline
  HalfOpen = distinct Pipeline
  Closed = distinct Pipeline

typestate Pipeline:
  consumeOnTransition = false
  strictTransitions = false
  states Open, HalfOpen, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> HalfOpen
    Open -> Closed
    HalfOpen -> Closed

proc `=destroy`(x: var Open) {.destructorTransition.} =
  ## Bridges Open -> Closed via Nim's `=destroy` injection. Lets the
  ## test proc bodies leave var-Open locals at non-terminal Open at
  ## fall-through without firing CFG-001 — the destructor covers the
  ## exit edge. Required so the test's focus is on the
  ## `findTransitionByCalleeAndArgStates` overload-lookup path
  ## rather than the surrounding param-leak validation.
  discard

proc mt(a: sink Open, n: int, b: var Open): HalfOpen {.transition.} =
  ## Mixed-param transition: `sink Open` at proc position 0 (the
  ## macro-required state-typed first param), non-typestate `int` at
  ## position 1, `var Open` at position 2 (typestate-bearing
  ## trailing param).
  ## `typestatedParams` = [TP(b, paramIndex=2)] (sink `a` is not
  ## pre-populated per round-2's `var T`-only scope; `n` is not a
  ## state type).
  ## At call sites with both `a` and `b` resolving to tracked Open
  ## locals, `argStates` = [some("Open"), none, some("Open")]. The
  ## position-0 sourceState check folds the first constraint into the
  ## first-param match; the new loop iterates `typestatedParams` and
  ## checks `argStates[paramIndex=2]` against `b.stateType="Open"`.
  discard n
  # `b` will be released via the registered Open `=destroy` at
  # fall-through (destructorTransition short-circuit) — no explicit
  # advancement required here.
  result = HalfOpen(a.Pipeline)

proc finalize(h: sink HalfOpen): Closed {.transition.} =
  ## Terminal consumer for the merged HalfOpen.
  result = Closed(h.Pipeline)

proc drive(a, b: var Open) {.notATransition.} =
  ## var-init binding path: `var f = mt(a, 5, b)`:
  ##   1. buildArgStatesFromCall sees a=Open at position 0, the
  ##      non-tracked literal `5` at position 1, b=Open at position 2
  ##      -> argStates = [some("Open"), none, some("Open")].
  ##   2. applyCallTransitions iterates the call args; `a` is sink-
  ##      consumed by mt (dropped), `b` is var-param (stays tracked).
  ##   3. tryBindLocalFromCallInit calls
  ##      findTransitionByCalleeAndArgStates("mt", argStates).
  ##      Round-5 fix: iterate typestatedParams ([(b, paramIndex=2)]),
  ##      check argStates[2]=some("Open") vs tp.stateType="Open" ->
  ##      match. Pick the registered `mt` overload.
  ##      Pre-round-5 the index `j=2` indexed into
  ##      typestatedParams[2] (len 1) — OOB guard triggered, ok=false,
  ##      proc rejected -> `f` would not bind to HalfOpen, downstream
  ##      logic mis-tracking ensues.
  ##   4. `f` binds as HalfOpen.
  ## `b` is still tracked at Open at fall-through; the registered
  ## Open destructor covers it. `a` was consumed by mt's sink.
  ## `f` (HalfOpen, non-terminal) — no destructor on HalfOpen, so to
  ## avoid CFG-001 on `f` we discard via finalize below.
  var f = mt(a, 5, b)
  discard finalize(f)

verifyTypestates()

# Runtime smoke — exercise the call site at least once to ensure the
# bound proc is exported and resolvable.
proc smoke() {.notATransition.} =
  var a {.used.}: Open
  var b {.used.}: Open
  drive(a, b)

smoke()
echo "cfg_analyzer_mixed_typestate_params ok"
