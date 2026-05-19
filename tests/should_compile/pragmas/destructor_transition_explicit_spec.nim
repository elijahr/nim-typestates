## Test: Two-arg {.destructorTransition: Src -> Dst.} form on a state-typed param.
##
## Verifies the two-arg form's spec validation succeeds when SrcState
## matches the destructor's param type and DstState is a declared
## terminal of the typestate.
import ../../../src/typestates

type
  Connection = object
    socketFd: int

  Active = distinct Connection
  Halfopen = distinct Connection
  Closed = distinct Connection
  Aborted = distinct Connection

typestate Connection:
  consumeOnTransition = false
  strictTransitions = false
  states Active, Halfopen, Closed, Aborted
  initial:
    Active
  terminal:
    Closed
    Aborted
  transitions:
    Active -> Halfopen
    Active -> Aborted
    Halfopen -> Closed

proc `=destroy`(c: var Halfopen) {.destructorTransition: Halfopen -> Closed.} =
  discard

verifyTypestates()
echo "destructor_transition_explicit_spec ok"
