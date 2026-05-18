## Test (Round-4 Finding #2/#3, fallback positive — no overload matches
## call-site arg state): when a `var f = tx(seed)` call cannot resolve
## to any registered overload because the arg's source-state matches
## none of the registered sources, the analyzer must NOT bind the LHS
## to a phantom destination. The conservative behavior (no LHS binding)
## is preserved, so the natural Nim-level error (type mismatch on the
## call expression) is what surfaces.
##
## Validates the round-4 fallback contract:
## `findTransitionByCalleeAndArgStates` returns `none(RegisteredProc)`
## when no overload matches, and `tryBindLocalFromCallInit` honors that
## by not adding a `LocalTypestate` to the live-set. Without round-4 the
## lookup would bind the LHS to whichever overload happened to be
## last-registered, potentially suppressing the natural error or
## emitting a misleading downstream CFG diagnostic. With round-4 the
## bug surfaces as the natural Nim type mismatch the user expects.
##
## The arg is a `var T` typestated param (pre-populated by round-2) so
## the source-state is observable to the analyzer's helper.
# expects: "type mismatch"
import ../../../src/typestates

type
  FileObj = object
    n: int

  Fresh = distinct FileObj
  Working = distinct FileObj
  Stale = distinct FileObj
  Disposed = distinct FileObj

typestate FileCtx:
  consumeOnTransition = false
  strictTransitions = false
  states Fresh, Working, Stale, Disposed
  initial:
    Fresh
    Stale
  terminal:
    Disposed
  transitions:
    Fresh -> Working
    Working -> Disposed
    Stale -> Disposed

proc tx(f: sink Fresh): Working {.transition.} =
  ## First overload: Fresh -> Working.
  result = Working(f.FileObj)

proc tx(f: sink Working): Disposed {.transition.} =
  ## Second overload (registered AFTER): Working -> Disposed.
  ## Pre-round-4 a callsite with a NON-matching arg state (a `Stale`
  ## value) would still bind the LHS to whichever overload won the
  ## name-only countdown loop. Round-4 source-state-aware lookup
  ## returns `none` for the no-match case so the LHS binding is
  ## correctly absent.
  result = Disposed(f.FileObj)

proc breakdown(seed: var Stale): Disposed {.transition.} =
  ## `seed: var Stale` is pre-populated by round-2 -> live-set has
  ## seed in state Stale. `tx(seed)` has no matching overload (no
  ## `tx(Stale)` registered). The natural Nim error surfaces. Round-4
  ## must not invent a phantom LHS binding that suppresses it.
  var f {.used.} = tx(seed)
  result = Disposed(FileObj(n: 0))

verifyTypestates()
