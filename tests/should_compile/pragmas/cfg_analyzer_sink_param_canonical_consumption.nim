## Test (Round-14 Gemini r13 HIGH — CFG-001 negative: canonical
## sink-param consumption shape stays clean). The canonical
## `result = Dst(s.Base)` shape MUST continue to verify cleanly after
## the round-14 pre-population reversal that tracks sink params
## symmetrically with `var T` params. This is the regression-prevention
## test for the original round-9 rationale that motivated the (now
## removed) `if tp.isSink: continue` skip.
##
## The body consumes `s` via the conversion-consume path:
## `applyCallTransitions` detects `Closed` (the destination state type
## name) as a state-type callee and routes `consumeLocalsInSubtree`
## across the conversion's args, dropping the underlying tracked local
## `s` (resolved via `extractTrackedLocal`'s recursive `nnkDotExpr`
## unwrap of `s.File`).
##
## Pre-round-14: clean (because pre-population skipped the sink
## param). Post-round-14: clean (because the canonical conversion
## consumes the now-tracked sink param before the fall-through exit
## edge runs).
import ../../../src/typestates

type
  File = object
    h: int

  Open = distinct File
  Closed = distinct File

typestate File:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Closed

proc tx(s: sink Open): Closed {.transition.} =
  ## Canonical sink-T transition body. `Closed(s.File)`:
  ##   - `Closed` is a registered state-type name -> conversion-consume.
  ##   - `s.File` resolves via `extractTrackedLocal` to `s`.
  ##   - `consumeLocalsInSubtree` drops `s` from the live-set.
  ## Fall-through then sees an empty (sink-param-wise) live-set; clean.
  result = Closed(s.File)

verifyTypestates()
echo "cfg_analyzer_sink_param_canonical_consumption ok"
