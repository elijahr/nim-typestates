## Test (CFG-001 negative — continue with terminal-state local): a
## while-body declares a typestate-bearing local that reaches a terminal
## state before the `continue` point. The continue exit edge accepts
## because all tracked body-locals are terminal at the edge — mirroring
## the break handler's terminal-accept path.
##
## Per §3.3 loop handling + continue: the continue exit edge runs
## validateExitEdge, which accepts terminal locals (and locals with a
## registered `{.destructorTransition.}`). This fixture exercises the
## terminal-accept path of the continue handler added in round 11.
import ../../../src/typestates

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
  ## while-body declares `done: Locked` (terminal). The continue exit
  ## edge sees only terminal-state body-locals; CFG-001 accepts.
  var n = 3
  while n > 0:
    var done {.used.}: Locked
    if skip:
      continue
    dec n
  result = Locked(g)

verifyTypestates()
echo "cfg_analyzer_continue_terminal_local ok"
