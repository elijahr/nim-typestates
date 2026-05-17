## Test: destructorTransition pragma on a multi-param generic typestate.
##
## Lands the 3.1.b.2 destructorTransition feature in a multi-type-param
## generic context. The destructor's `var T` source-state type must be
## resolvable when the typestate has [T1, T2] parameters, and the
## attachment-aware path inference (Doc A §3.1) must propagate the
## param bindings into the registry entry.
##
## Bug-class: regression guard for pragma macro interaction with the
## constrained-multi-param generic registration path.
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
) {.destructorTransition.} =
  var underlying = Conn[Proto, Addr](o)
  underlying.closed = true
  discard underlying

verifyTypestates()
echo "multi_param_destructor_transition ok"
