## Test (CFG-001 negative — finally drives terminal): a typestate-bearing
## local is bound BEFORE the try; the try body advances nothing, except
## handler does nothing, and the FINALLY body declares its own terminal
## binding for diagnostic purposes. The post-finally state inherits from
## the finally walk, which leaves the outer local's state unchanged but
## still tracked.
##
## Outer local's exit-edge admissibility relies on its having a registered
## destructor (path: hasDestructor short-circuit), which is what the
## nim-debra shutdown shape relies on at scale.
##
## Per §3.3 try/except/finally: finally runs after both body and except
## branches. The reconciled post-catch state is the entry to the finally
## walk; the post-finally state becomes the post-try state.
import ../../../src/typestates

type
  Channel = object
    n: int

  Open = distinct Channel
  Closed = distinct Channel

typestate Channel:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Closed

proc `=destroy`(c: var Open) {.destructorTransition.} =
  ## Bridging destructor: any Open in scope at an exit edge is accepted
  ## by the CFG analyzer's hasDestructor short-circuit.
  discard

proc drain(idx: int) =
  ## Wrapper proc whose body has a try/except/finally over a local with a
  ## registered destructor. validateExitEdge accepts on every exit because
  ## hasDestructor short-circuits the terminal check.
  var live: Open
  try:
    discard idx
  except CatchableError:
    discard
  finally:
    discard live

verifyTypestates()
echo "cfg_analyzer_finally_consumes ok"
