## Test (CFG-001 negative — sink-consume composition, Finding #1 scope (d)):
## the shape `let f = consume(g)` composes (a) call-tracking with (c)
## init-binding. The call's `sink` parameter consumes `g` from tracking,
## and the LHS `f` is bound to the call's registered destination.
##
## Pattern exercised:
##
##   var g = open(...)            # var-init binds g to Pinned (non-terminal)
##   let f = unpin(g)             # unpin: Pinned -> Released (terminal)
##                                # sink-consumes g (drop from tracking),
##                                # binds f to Released (terminal).
##
## Both halves of the composition matter: pre-fix, `g` would still be
## tracked at fall-through (CFG-001 false positive), AND `f` would never
## be tracked at all (subsequent uses of `f` could violate typestate
## invariants without the analyzer noticing).
import ../../../src/typestates

type
  Pin = object
    n: int

  Pinned = distinct Pin
  Released = distinct Pin

typestate Pin:
  consumeOnTransition = false
  strictTransitions = false
  states Pinned, Released
  initial:
    Pinned
  terminal:
    Released
  transitions:
    Pinned -> Released

proc fresh(): Pinned {.notATransition.} =
  ## Factory producing a Pinned (non-terminal). Not a registered
  ## transition — the analyzer cannot infer its result.
  Pinned(Pin(n: 1))

proc unpin(p: sink Pinned): Released {.transition.} =
  ## Registered transition consuming Pinned, producing terminal Released.
  result = Released(p.Pin)

proc useScope() {.notATransition.} =
  ## Sink-consume composition: `g` is consumed by `unpin(g)`; `f` is
  ## bound to the registered terminal destination.
  var g: Pinned
  g = Pinned(Pin(n: 1))
  let f = unpin(g)
  discard f

verifyTypestates()
echo "cfg_analyzer_tracks_sink_consume ok"
