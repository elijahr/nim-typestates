## Test (CFG-001 — continue inside loop bypasses terminal-advancing path):
## a while-body declares a typestate-bearing local in a non-terminal
## state, then `continue`s before any transition could advance it. The
## continue point is an exit edge from the current loop iteration;
## validateExitEdge must reject because the local is not in a terminal
## state and has no destructor.
##
## Per §3.3 loop handling + continue: continue jumps back to the loop
## header, ending the current iteration's body scope. Body-introduced
## locals that escape via continue must satisfy the same exit-edge
## contract as locals escaping via break — otherwise a non-terminal
## body-local that hits continue silently leaks past the analyzer
## (parallel gap to the break handler's existing validation).
# expects: "has not reached a terminal state at this continue"
# expects: "Latch"
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
  ## while-body binds `l: Latch` (non-terminal, no destructor), then
  ## continues unconditionally based on a flag. The continue exit edge
  ## fires CFG-001 — mirrors the break-handler behavior in
  ## cfg_analyzer_while_break_skips_terminal.
  var n = 3
  while n > 0:
    var l {.used.}: Latch
    if skip:
      continue
    dec n
  result = Locked(g)

verifyTypestates()
