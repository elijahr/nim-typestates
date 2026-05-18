## Test (CFG-001 negative — continue with destructor-backed local): a
## while-body declares a typestate-bearing local that is non-terminal at
## the `continue` point but whose type has a registered
## `{.destructorTransition.}`. The continue exit edge accepts via the
## destructor short-circuit — Nim's `=destroy` will fire the bridging
## transition when the iteration scope ends.
##
## Per §3.3 loop handling + continue: validateExitEdge at the continue
## point accepts EITHER terminal-state locals OR locals whose type has
## a destructor that bridges to terminal. This fixture exercises the
## destructor-accept path of the continue handler added in round 11,
## paralleling cfg_analyzer_branch_local_with_destructor.
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
  ## Bridges Live -> Dropped; injected by Nim at every scope exit that
  ## leaves a Live local in scope, including iteration-scope close at
  ## `continue`.
  discard

type
  Hatch = object
    n: int

  Latch = distinct Hatch
  Locked = distinct Hatch

typestate Hatch:
  consumeOnTransition = false
  strictTransitions = false
  states Latch, Locked
  initial:
    Latch
  terminal:
    Locked
  transitions:
    Latch -> Locked

proc cycle(g: sink Latch, skip: bool): Locked {.transition.} =
  ## while-body declares `aux: Live` (non-terminal but destructor-backed).
  ## The continue exit edge accepts via the destructor short-circuit.
  var n = 3
  while n > 0:
    var aux {.used.}: Live
    if skip:
      continue
    dec n
  result = Locked(g)

verifyTypestates()
echo "cfg_analyzer_continue_local_with_destructor ok"
