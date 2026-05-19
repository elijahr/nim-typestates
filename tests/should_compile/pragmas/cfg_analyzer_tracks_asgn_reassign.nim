## Test (CFG-001 negative — asgn-reassign tracking, Finding #1 scope (c)):
## the shape `f = factory()` (`nnkAsgn` whose RHS is a registered transition
## call producing a typestated value) advances an already-tracked local's
## state to the call's registered destination, **without** requiring the
## RHS to consume the same local — pure-factory transitions are also
## tracked.
##
## Pattern exercised:
##
##   var seed: SlotIdle           # tracked as SlotIdle (non-terminal)
##   var f: SlotActive            # tracked as SlotActive (terminal) — pre-bound
##   f = produce(seed)            # produce: SlotIdle -> SlotActive
##                                # consumes seed (terminal), rebinds f
##                                # to SlotActive (still terminal)
##
## Distinct from `cfg_analyzer_tracks_asgn_init.nim`: there the LHS was
## introduced by a `var` section; here the LHS is rebound after declaration
## via an `nnkAsgn` node. The reassign-handler path of walkCfg must
## (1) apply the call's transition to its tracked arg, and (2) update
## the LHS local's tracked state to the registered destination.
import ../../../src/typestates

type
  Slot = object
    n: int

  SlotIdle = distinct Slot
  SlotActive = distinct Slot

typestate Slot:
  consumeOnTransition = false
  strictTransitions = false
  states SlotIdle, SlotActive
  initial:
    SlotIdle
  terminal:
    SlotActive
  transitions:
    SlotIdle -> SlotActive

proc produce(s: sink SlotIdle): SlotActive {.transition.} =
  ## Registered transition: SlotIdle -> SlotActive (terminal).
  result = SlotActive(s.Slot)

proc cycle() {.notATransition.} =
  ## Reassignment shape. After `f = produce(seed)`:
  ##   - seed is consumed (terminal-reach => dropped from tracking).
  ##   - f is re-bound to SlotActive (terminal).
  var seed: SlotIdle
  var f: SlotActive
  f = produce(seed)
  discard f

verifyTypestates()
echo "cfg_analyzer_tracks_asgn_reassign ok"
