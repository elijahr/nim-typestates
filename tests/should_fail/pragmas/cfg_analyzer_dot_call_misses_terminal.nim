## Test (CFG-001 positive — dot-call advances to non-terminal, round-2
## Finding #1): a registered transition called in dot-call syntax
## `f.transition()` advances the tracked local to a NON-terminal
## intermediate state. With no subsequent consumption of that local, the
## fall-through exit edge must reject (CFG-001).
##
## Companion to the should_compile dot-call positive test: confirms the
## new dot-call recognition does not OVER-track (silently treating every
## dot-call as terminal-equivalent) — only non-terminal destinations
## remain tracked and continue to require terminal-reaching consumption.
## The receiver `call[0][0]` advancement is keyed off the same
## destination-state logic as the prefix-call path.
##
## Uses a non-sink transition (`var T` first param) so the analyzer
## advances the receiver in place to the registered destination state
## rather than dropping it (sink-consume path). The non-terminal Half
## destination keeps the receiver tracked, and the absent finalize
## consume leaves it leaked at fall-through.
# expects: "has not reached a terminal state"
# expects: "Half"
# expects: "Closed"
import ../../../src/typestates

type
  Resource = object
    n: int

  Open = distinct Resource
  Half = distinct Resource
  Closed = distinct Resource

typestate Resource:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Half, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Half
    Half -> Closed
    Open -> Closed

proc halve(r: var Open): Half {.transition, skipCfgAnalysis.} =
  ## Non-sink `var T` first param — non-consuming. Round-1 `applyCall-
  ## Transitions` advances the tracked receiver in place to the
  ## registered destination (Half) rather than dropping it.
  ## `{.skipCfgAnalysis.}` opts this body OUT of analysis so the dummy
  ## construction doesn't trip CFG-001 / CFG-003 itself; the analyzer
  ## still sees `halve` as a registered transition for the per-call
  ## advancement at use sites.
  result = Half(Resource(n: 0))

proc finalize(r: sink Half): Closed {.transition.} =
  ## Terminal destination — defined so the typestate's Half -> Closed
  ## edge has an implementation, but NOT called from `primary`'s body so
  ## the dot-call-advanced local stays leaked.
  result = Closed(r.Resource)

proc primary(seed: sink Open): Closed {.transition.} =
  ## Body: dot-call `f.halve()` advances the body-local `f` (Open) to
  ## Half (non-terminal). No subsequent `f.finalize()` -> CFG-001 at
  ## fall-through. The pre-fix analyzer would have left `f` unrecognized
  ## (dot-call receiver not iterated), so this fixture would have
  ## silently passed. Post-fix the receiver is treated as the implicit
  ## first arg and `f` is advanced to Half; the fall-through check fires.
  result = Closed(seed.Resource)
  var f: Open
  discard f.halve()
  # f is Half (non-terminal). No finalize -> CFG-001 here.

verifyTypestates()
