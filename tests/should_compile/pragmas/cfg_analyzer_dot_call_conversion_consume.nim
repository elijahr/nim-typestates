## Test (CFG-001 negative — dot-call conversion-consume, round-3
## Finding #1, verify.nim:424): a registered transition proc body
## producing its result via the dot-call form `src.Dst()` (where `Dst`
## is a registered state-type name and `src` is a typestate-bearing
## param resolved through `bindLocalsFromIdentDefs` / typestated-params
## pre-population) must consume `src` from the live-set.
##
## Pre-fix the conversion-consume early return iterated only
## `call[1..N-1]`, missing the receiver `call[0][0]` for dot-call
## conversions. A body like
##
##   proc step(s: sink Open): Closed {.transition.} =
##     result = s.Closed
##
## (parses as `nnkCall(nnkDotExpr(s, Closed))` with `call.len == 1` —
## the receiver is at `call[0][0]`) left `s` tracked at the fall-through
## and false-fired CFG-001 inside every transition body using the
## dot-call conversion form. Post-fix the
## receiver is folded into `argNodes` before the `isStateTypeName`
## conversion-consume check, so both prefix (`Closed(s.File)`) and
## dot-call (`s.Closed`) variants route through the same consume path.
import ../../../src/typestates

type
  Channel = object
    fd: int

  Open = distinct Channel
  Closed = distinct Channel

typestate Channel:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Closed

proc shutdown(c: sink Open): Closed {.transition.} =
  ## Canonical dot-call conversion-consume form: `result = c.Closed()`
  ## is parsed as `nnkCall(nnkDotExpr(c, Closed))` where the trailing
  ## identifier `Closed` is a registered state-type name. The conversion
  ## consumes `c` (the receiver / implicit arg at `call[0][0]`).
  result = c.Closed()

proc useShutdown() {.notATransition.} =
  var c: Open
  discard shutdown(c)

verifyTypestates()
useShutdown()
echo "cfg_analyzer_dot_call_conversion_consume ok"
