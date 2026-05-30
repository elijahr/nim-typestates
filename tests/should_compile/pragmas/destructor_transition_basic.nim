## Test: Basic single-arg {.destructorTransition.} on a state-typed param.
##
## Verifies the canonical single-arg form: the typestate declares exactly
## one terminal state, so the destructor's destination is inferred as the
## typestate's terminalStates set without an explicit spec.
##
## Source state is the destructor's `var T` parameter type (state-typed
## param path — §3.1 path (a)). No §3.7 attachment registry involvement.
##
## TODO (3.1.b.4): the attached-object-param variant of this test (where
## the destructor param is bound to a typestate via the §3.7 attachment
## pragma instead of being a state itself) is deferred until the
## attachment pragma is implemented.
import ../../../src/typestates

type
  Resource = object
    handle: int

  Open = distinct Resource
  Closed = distinct Resource

typestate Resource:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Closed

proc `=destroy`(r: var Open) {.destructorTransition.} =
  discard

verifyTypestates()
echo "destructor_transition_basic ok"
