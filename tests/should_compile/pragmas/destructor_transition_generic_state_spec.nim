## Test: Two-arg `{.destructorTransition: Src -> Dst.}` with GENERIC state types.
##
## Regression guard for v0.9.2 bracket-asymmetry bug: parser stored
## terminal state reprs verbatim (e.g. `"Closed[Proto, Addr]"`) while
## the validator at `pragmas.nim:985` compared against
## `extractTypeName(spec[2])` output (bare `"Closed"`). The membership
## check `parsedDstStateName notin graph.terminalStates` therefore
## rejected every two-arg destructorTransition whose target was a
## generic terminal state.
##
## This fixture exercises the exact failure path: a generic typestate
## with a generic terminal state, and a destructor that names the
## transition explicitly with the two-arg spec form.
import ../../../src/typestates

type
  Conn[Proto, Addr] = object
    p: Proto
    a: Addr
    closed: bool

  Opened[Proto, Addr] = distinct Conn[Proto, Addr]
  Closed[Proto, Addr] = distinct Conn[Proto, Addr]

typestate Conn[Proto, Addr]:
  consumeOnTransition = false
  strictTransitions = false
  states Opened[Proto, Addr], Closed[Proto, Addr]
  initial:
    Opened[Proto, Addr]
  terminal:
    Closed[Proto, Addr]
  transitions:
    Opened[Proto, Addr] -> Closed[Proto, Addr]

proc `=destroy`[Proto, Addr](
    o: var Opened[Proto, Addr]
) {.destructorTransition: Opened -> Closed.} =
  var underlying = Conn[Proto, Addr](o)
  underlying.closed = true
  discard underlying

verifyTypestates()
echo "destructor_transition_generic_state_spec ok"
