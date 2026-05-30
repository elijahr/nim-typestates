## Test (Round-4 Finding #1, CFG-001 negative — branch-local with
## destructor): a typestate-bearing local declared inside one branch
## whose type has a registered `{.destructorTransition.}` is accepted
## at branch-close even without explicit consumption — the destructor's
## bridging transition fires when the local goes out of scope. Mirrors
## the existing destructor short-circuit in `validateExitEdge`.
##
## Pattern exercised inside a registered `{.transition.}` proc body:
##
##   if cond:
##     var aux: Live       # Live has a {.destructorTransition.} -> Dropped
##     # branch closes WITHOUT consuming aux; destructor handles it.
##   # Round-4 -> clean (destructor short-circuit at branch-close).
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
  ## Bridges Live -> Dropped; injected by Nim at every scope exit that
  ## leaves a Live local in scope — including branch-close.
  discard

proc work(c: sink Cold, cond: bool): Warm {.transition.} =
  ## Branch-local `aux` is non-terminal at branch-close but has a
  ## registered `{.destructorTransition.}`. Round-4 branch-close
  ## validation accepts via the destructor short-circuit, the same way
  ## `validateExitEdge` accepts at return / raise / fall-through.
  if cond:
    var aux {.used.}: Live
  result = Warm(c)

verifyTypestates()
echo "cfg_analyzer_branch_local_with_destructor ok"
