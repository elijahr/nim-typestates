## Test (CFG-001 negative): early `return` inside a registered transition
## proc whose body owns a typestate-bearing local IS allowed when that
## local's type has a registered `{.destructorTransition.}`.
##
## Per §3.3, Nim's =destroy injection guarantees the bridging transition
## fires on the return edge, so the analyzer's hasDestructor short-circuit
## accepts the exit edge without requiring an explicit transition.
##
## The analyzer's scope (§3.3 "scope detection") covers bodies of procs in
## `registeredProcs` (transition / destructorTransition / notATransition).
## Here we use `pump` (a {.transition.} proc) whose body declares an `Aux`
## local of typestate `Bus` (live, has destructor) that is auto-consumed
## by Bus's =destroy on the early-return branch.
import ../../../src/typestates

type
  Pulse = object
    n: int

  Cold = distinct Pulse
  Warm = distinct Pulse

typestate Pulse:
  consumeOnTransition = false
  strictTransitions = false
  states Cold, Warm
  initial:
    Cold
  terminal:
    Warm
  transitions:
    Cold -> Warm

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
  ## Bridges Live -> Dropped; injected by Nim at every exit edge that
  ## leaves a Live local in scope.
  discard

proc pump(c: sink Cold, early: bool): Warm {.transition.} =
  ## Registered proc whose body declares `aux: Live`. On the early-return
  ## branch, `aux` is non-terminal but has a registered destructor — the
  ## analyzer accepts (CFG-001 short-circuit on hasDestructor).
  var aux: Live
  if early:
    result = Warm(c)
    return
  result = Warm(c)
  discard aux

verifyTypestates()
echo "cfg_analyzer_destructor_covers_early_return ok"
