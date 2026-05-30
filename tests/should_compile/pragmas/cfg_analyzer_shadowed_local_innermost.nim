## Test (Finding #3 — innermost-first shadowing): two typestate-bearing
## locals share the same identifier `x` across nested scopes. The OUTER
## `x` is a non-terminal state with NO registered destructor; the INNER
## shadow is the terminal state. `discard x` inside the inner block
## must resolve to the INNER `x` (terminal — accepted by CFG-003); pre-fix,
## the forward-iterating discard handler would resolve to the OUTER `x`
## (non-terminal, no destructor — would emit CFG-003 false positive).
##
## After the inner block ends, the outer `x` (still tracked) is consumed
## explicitly via a registered transition call, so fall-through is clean.
##
## Pattern exercised:
##
##   var x: Channel       # outer; non-terminal, NO destructor
##   block:
##     var x: Sealed     # inner shadow; terminal
##     discard x         # innermost-first resolves to inner -> accepted
##   discard seal(x)     # consume the outer via registered transition
##                        # Channel -> Sealed (terminal)
##
## Pre-fix (forward search): discard inside the inner block resolves to
## outer `x: Channel` -> not terminal -> CFG-003 false positive.
##
## Post-fix (innermost-first via countdown): inner `x: Sealed` wins,
## accepted; outer is consumed cleanly by the `seal` call.
import ../../../src/typestates

type
  Wire = object
    n: int

  Channel = distinct Wire
  Sealed = distinct Wire

typestate Wire:
  consumeOnTransition = false
  strictTransitions = false
  states Channel, Sealed
  initial:
    Channel
  terminal:
    Sealed
  transitions:
    Channel -> Sealed

proc seal(c: sink Channel): Sealed {.transition.} =
  ## Registered transition: Channel -> Sealed (terminal).
  result = Sealed(c.Wire)

proc useShadow() {.notATransition.} =
  var x: Channel
  block:
    var x: Sealed
    discard x
  discard seal(x)

verifyTypestates()
echo "cfg_analyzer_shadowed_local_innermost ok"
