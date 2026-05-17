## Test (CFG-002 — case-branch reconciliation): one `of` arm of a `case`
## leaves a typestate-bearing local in a state that disagrees with the
## other arms (and is non-terminal). `reconcileBranches` cannot merge:
## CFG-002 fires at the join point.
##
## Per §3.3: case-branch reconciliation is symmetric with if-branch
## reconciliation. Mixing the diverging state with terminal states still
## fails the terminal-union exception because the diverging state itself
## is non-terminal.
# expects: "has inconsistent state across branches"
# expects: "Done"
# expects: "Running"
import ../../../src/typestates

type
  Bus = object
    n: int

  Open = distinct Bus
  Sealed = distinct Bus

typestate Bus:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Sealed
  initial:
    Open
  terminal:
    Sealed
  transitions:
    Open -> Sealed

type
  Job = object
    n: int

  Started = distinct Job
  Running = distinct Job
  Done = distinct Job

typestate Job:
  consumeOnTransition = false
  strictTransitions = false
  states Started, Running, Done
  initial:
    Started
  terminal:
    Done
  transitions:
    Started -> Running
    Running -> Done

proc route(b: sink Open, n: int): Sealed {.transition.} =
  ## Three of-arms declare `s` at different states; the middle arm picks
  ## non-terminal `Running` while the others pick terminal `Done`. The
  ## terminal-union exception only applies when ALL branches reach a
  ## terminal — here one branch does not, so CFG-002 must fire.
  case n
  of 0:
    var s: Done
    discard s
  of 1:
    var s: Running
    discard s
  else:
    var s: Done
    discard s
  result = Sealed(b)

verifyTypestates()
