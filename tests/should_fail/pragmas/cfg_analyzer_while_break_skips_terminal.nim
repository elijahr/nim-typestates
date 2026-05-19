## Test (CFG-001 — break inside loop bypasses terminal-advancing path):
## a while-body declares a typestate-bearing local in a non-terminal
## state, then `break`s before any transition could advance it. The break
## point is an exit edge; validateExitEdge must reject because the local
## is not in a terminal state and has no destructor.
##
## Per §3.3 loop handling + break: break is an unconditional exit from the
## enclosing loop scope. Locals introduced inside the body that escape via
## break must satisfy the same exit-edge contract as proc-level returns.
# expects: "has not reached a terminal state at this break"
# expects: "Open"
import ../../../src/typestates

type
  Gate = object
    n: int

  Open = distinct Gate
  Sealed = distinct Gate

typestate Gate:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Sealed
  initial:
    Open
  terminal:
    Sealed
  transitions:
    Open -> Sealed

proc cycle(g: sink Open, stop: bool): Sealed {.transition.} =
  ## while-body binds `o: Open` (non-terminal, no destructor), then breaks
  ## unconditionally based on a flag. The break exit edge fires CFG-001.
  var n = 3
  while n > 0:
    var o {.used.}: Open
    if stop:
      break
    dec n
  result = Sealed(g)

verifyTypestates()
