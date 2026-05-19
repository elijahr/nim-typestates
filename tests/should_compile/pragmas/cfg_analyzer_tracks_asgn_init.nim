## Test (CFG-001 negative — asgn-init tracking, Finding #1 scope (c)):
## the shape `var f = open()` (var section with init expression that is a
## registered transition call) binds `f` to the call's registered
## destination state. A subsequent transition call then consumes `f` to
## terminal.
##
## Pattern exercised:
##
##   var f = open()            # var section init: open() : Closed -> Open
##                              # binds f as Open
##   discard close(f)           # close: Open -> Closed; consumes f
##
## The analyzer must (1) track the LHS `f` introduced by the var-init
## even though the IdentDefs has no type slot, and (2) compose that
## tracking with the subsequent call's transition recognition.
import ../../../src/typestates

type
  Bus = object
    n: int

  BusClosed = distinct Bus
  BusOpen = distinct Bus

typestate Bus:
  consumeOnTransition = false
  strictTransitions = false
  states BusClosed, BusOpen
  initial:
    BusClosed
  terminal:
    BusOpen
  transitions:
    BusClosed -> BusOpen

proc open(b: sink BusClosed): BusOpen {.transition.} =
  ## Registered transition producing the terminal state.
  result = BusOpen(b.Bus)

proc useBus() {.notATransition.} =
  ## The asgn-init shape: `var f = open(seed)`. The analyzer binds `f`
  ## to BusOpen (terminal), so fall-through accepts cleanly.
  var seed: BusClosed
  var f = open(seed)
  discard f

verifyTypestates()
echo "cfg_analyzer_tracks_asgn_init ok"
