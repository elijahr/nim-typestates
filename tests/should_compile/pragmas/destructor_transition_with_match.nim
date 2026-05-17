## Test: destructorTransition body may contain a match-style consumption
## over the typestate's terminals (when destructor body actually does work).
##
## Sanity check that the destructor body is real Nim code — the macro
## emits destrDef unchanged after validation, so any valid =destroy body
## is accepted. This fixture exercises a body that touches the wrapped
## object's fields (the typical use case for resource cleanup).
import ../../../src/typestates

type
  Handle = object
    fd: int
    cleaned: bool

  Owned = distinct Handle
  Released = distinct Handle

typestate Handle:
  consumeOnTransition = false
  strictTransitions = false
  states Owned, Released
  initial:
    Owned
  terminal:
    Released
  transitions:
    Owned -> Released

proc `=destroy`(o: var Owned) {.destructorTransition.} =
  var underlying = o.Handle
  underlying.cleaned = true
  # `discard` of a terminal state local is acceptable; v0.9.0 CFG analyzer
  # lands in sub-phase 3.1.b.3 (this fixture does not assert analyzer
  # behavior, only the pragma's macro-time validation).
  discard underlying

verifyTypestates()
echo "destructor_transition_with_match ok"
