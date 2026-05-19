## Test (Round-14 Gemini r13 HIGH — CFG-001 negative: sink-param
## non-consumption is accepted when the param's type has a registered
## `{.destructorTransition.}`). After round-14 the analyzer pre-populates
## sink-T params symmetrically with `var T` params; a non-consume body
## ordinarily fires CFG-001 at fall-through. The destructor short-circuit
## in `validateExitEdge` accepts the leak when Nim's `=destroy` injection
## bridges the param to a terminal state at scope-exit.
##
## Pattern exercised:
##
##   proc `=destroy`(h: var Live) {.destructorTransition.} = discard
##   proc tx(s: sink Live): Dropped {.transition.} =
##     result = Dropped(Bus(handle: 0))   # `s` never consumed
##
## Pre-round-14: clean (pre-population skipped sink params entirely).
## Post-round-14: clean (sink param tracked; destructor short-circuit
## accepts the non-consume tail at fall-through).
import ../../../src/typestates

type
  Bus = object
    handle: int

  Live = distinct Bus
  Dropped = distinct Bus

typestate Bus:
  consumeOnTransition = false
  strictTransitions = false
  states Live, Dropped
  initial:
    Live
  terminal:
    Dropped
  transitions:
    Live -> Dropped

proc `=destroy`(h: var Live) {.destructorTransition.} =
  ## Bridges Live -> Dropped at scope-exit. The sink param `s` in `tx`
  ## relies on this destructor to reach a terminal state when the body
  ## does not consume it explicitly.
  discard

proc tx(s: sink Live): Dropped {.transition.} =
  ## Body never references `s`. `result` is built from a fresh `Bus`
  ## value. Round-14 pre-populates `s` into the live-set, but the
  ## destructor short-circuit in `validateExitEdge` accepts the
  ## fall-through exit because `Live` has a registered
  ## `{.destructorTransition.}`.
  result = Dropped(Bus(handle: 0))

verifyTypestates()
echo "cfg_analyzer_sink_param_destructor_coverage ok"
