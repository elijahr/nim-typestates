## Test: Single-arg destructorTransition over a typestate with multiple
## terminal states resolves destStates to the union of terminals.
##
## The destructor doesn't pin a single terminal; this models the case
## where the destructor consumes via a match-arm over all terminals.
## The two-arg form would be needed to pin one specific terminal — see
## destructor_transition_explicit_spec.nim for that variant.
import ../../../src/typestates

type
  Session = object
    id: int

  Live = distinct Session
  Drained = distinct Session
  Killed = distinct Session

typestate Session:
  consumeOnTransition = false
  strictTransitions = false
  states Live, Drained, Killed
  initial:
    Live
  terminal:
    Drained
    Killed
  transitions:
    Live -> Drained
    Live -> Killed

proc `=destroy`(s: var Live) {.destructorTransition.} =
  ## Single-arg form: destination resolves to the union @["Drained", "Killed"].
  discard

verifyTypestates()
echo "destructor_transition_match_terminals ok"
