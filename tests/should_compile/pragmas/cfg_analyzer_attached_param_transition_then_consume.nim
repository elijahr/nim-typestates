## Test: §3.7 attached `var` param survives a fall-through exit when a
## `{.destructorTransition.}` is registered against the attached
## holder type. Validates round-6 findings #6 (live-set pre-pop
## propagates attachedTypeName from TypestatedParam) AND that the
## destructor lookup keys on `attachedTypeName`, NOT on the resolved
## state name.
##
## The registered `{.transition.}` proc `processMailbox` takes a
## state-typed `sink Driver` (drives the transition's source -> dst
## edge) AND a non-state, attached-object `var Mailbox` (attached to
## typestate Drive with initial state Driver). The CFG analyzer's
## live-set pre-pop must enter `m` with stateType=Driver AND
## attachedTypeName=Mailbox. Destructor is registered against
## Mailbox, so destructor recognition at fall-through must key on
## attachedTypeName.
##
## Pre-round-6 the live-set pre-pop did NOT carry attachedTypeName,
## so destructor recognition keyed only on stateType (Driver) and
## missed the registered `=destroy(var Mailbox)` — false-firing
## CFG-001 on this fixture.
import ../../../src/typestates

type
  Driver = object
  Driven = object

typestate Drive:
  consumeOnTransition = false
  strictTransitions = false
  states Driver, Driven
  initial:
    Driver
  terminal:
    Driven
  transitions:
    Driver -> Driven

# Attached holder type. Destructor registers against `Mailbox`,
# keyed under "Mailbox" in destructorTypes (NOT under "Driver").
type Mailbox {.Drive: Driver.} = object
  payload: int

proc `=destroy`(m: var Mailbox) {.destructorTransition.} =
  ## Destructor closes the Mailbox holder at scope exit. Round-6
  ## lookup-key contract: destructorTypes["Mailbox"] (the attached
  ## type name) maps to typestate `Drive`.
  discard

# `{.transition.}` proc whose body the CFG analyzer walks. The
# state-typed `sink Driver` arg provides the source->dst edge that
# satisfies `{.transition.}` registration. The `var m: Mailbox` arg
# is the attached-object param that exercises live-set pre-pop with
# attachedTypeName.
proc processMailbox(src: sink Driver, m: var Mailbox): Driven {.transition.} =
  ## Round-6 fix: at proc entry, both `src` (state-typed; pre-pop is
  ## skipped because `sink` params aren't pre-populated — see
  ## `extractTypestatedParams` doc) and `m` (attached; stateType=
  ## Driver, attachedTypeName=Mailbox) are recognised. `m`'s
  ## fall-through exit is accepted because `hasDestructorFor`
  ## resolves via attachedTypeName="Mailbox".
  result = Driven()
  discard m.payload # keep `m` live; not a state-bearing op

var box: Mailbox
discard processMailbox(Driver(), box)
verifyTypestates()
echo "cfg_analyzer_attached_param_transition_then_consume ok"
