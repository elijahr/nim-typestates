## Test (v0.9.3 transitionError): a `{.destructorTransition.}` proc declared
## with `transitionError: "destroyed"` on a VALID terminal transition
## compiles cleanly.
##
## Exercises the two-arg `destructorTransition: Src -> Dst` form combined
## with a sibling `transitionError:` pragma. The destructor's transition
## is legal (Halfopen is non-terminal, ClosedScope is terminal, the
## transition is declared); the custom error string is harvested but
## never emitted.
import ../../../src/typestates

type
  Scope = object
  ActiveScope = distinct Scope
  Halfopen = distinct Scope
  ClosedScope = distinct Scope

typestate Scope:
  consumeOnTransition = false
  strictTransitions = false
  states ActiveScope, Halfopen, ClosedScope
  initial:
    ActiveScope
  terminal:
    ClosedScope
  transitions:
    ActiveScope -> Halfopen
    Halfopen -> ClosedScope

proc `=destroy`(
    h: var Halfopen
) {.
    destructorTransition: Halfopen -> ClosedScope,
    transitionError: "Halfopen scope must close before destruction"
.} =
  discard

verifyTypestates()
echo "destructor_transition_error_compiles ok"
