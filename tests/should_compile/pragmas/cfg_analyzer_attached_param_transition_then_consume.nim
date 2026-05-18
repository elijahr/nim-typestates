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
##
## Round-14 (Gemini r13 HIGH) closed the `if tp.isSink: continue`
## skip in `runCfgAnalyzer`'s pre-population loop. The sink-typed
## `src: sink Driver` param is now tracked at proc entry; the body
## constructs `result = Driven()` from a fresh value and does not
## reference `src`, so the round-14-tracked `src` needs a separate
## scope-exit bridge. A `=destroy(var Driver) {.destructorTransition.}`
## registers the Driver->Driven destructor; `validateExitEdge`'s
## destructor short-circuit accepts the fall-through. The fixture's
## original intent (attached-param + destructor-lookup-via-
## attachedTypeName for `m`) is unchanged; the Driver destructor is
## additive scaffolding for the sink param.
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

proc `=destroy`(d: var Driver) {.destructorTransition.} =
  ## Round-14 scaffolding: bridges Driver -> Driven at scope-exit so
  ## the round-14-tracked `src: sink Driver` param in `processMailbox`
  ## is accepted by `validateExitEdge`'s destructor short-circuit
  ## without requiring an explicit body-side consumption. Keeps the
  ## fixture's focus on the attached-param + attachedTypeName-keyed
  ## destructor lookup (the round-6 contract this fixture was
  ## designed to lock in).
  discard

# `{.transition.}` proc whose body the CFG analyzer walks. The
# state-typed `sink Driver` arg provides the source->dst edge that
# satisfies `{.transition.}` registration. The `var m: Mailbox` arg
# is the attached-object param that exercises live-set pre-pop with
# attachedTypeName.
proc processMailbox(src: sink Driver, m: var Mailbox): Driven {.transition.} =
  ## Round-14: at proc entry, both `src` (state-typed sink Driver,
  ## now pre-populated symmetrically with var params after the
  ## round-14 skip reversal) and `m` (attached; stateType=Driver,
  ## attachedTypeName=Mailbox) are recognised. `m`'s fall-through
  ## exit is accepted because `hasDestructorFor` resolves via
  ## attachedTypeName="Mailbox"; `src`'s fall-through exit is
  ## accepted because the round-14 scaffold `=destroy(var Driver)
  ## {.destructorTransition.}` bridges Driver -> Driven at
  ## scope-exit.
  result = Driven()
  discard m.payload # keep `m` live; not a state-bearing op

var box: Mailbox
discard processMailbox(Driver(), box)
verifyTypestates()
echo "cfg_analyzer_attached_param_transition_then_consume ok"
