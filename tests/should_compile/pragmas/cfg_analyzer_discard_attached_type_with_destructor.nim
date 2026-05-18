## Test (Round-9 Finding #2, CFG-003 negative — discard of an attached
## object-typed local consumed by an intrinsic wrapper, with the
## destructor registered against the OBJECT type): `discard move(m)`
## where `m: var Mailbox` is an attached param in a non-terminal state
## AND a `{.destructorTransition.}` is registered against the OBJECT
## TYPE `Mailbox` must NOT fire CFG-003 — Nim's `=destroy` injection
## bridges the moved-out temporary's scope exit to terminal.
##
## Pre-round-9 the discard handler's destructor lookup keyed `attachedKey`
## ONLY on the post-walk `result.locals[localIdx].attachedTypeName`.
## Intrinsic-consumer shapes (`discard move(m)`, `discard m.sink()`)
## consume the local inside the operand walk via
## `applyCallTransitions`'s intrinsic block, so `localIdx` falls back to
## -1 and `attachedKey` was forced to "". The destructor lookup then
## tried `exprStateName` only (the typestate STATE name, e.g.
## "Driver") and missed the destructor registered against the OBJECT
## type name ("Mailbox") — CFG-003 false-fired.
##
## Post-round-9: a parallel pre-walk capture
## `preWalkAttachedTypeName` mirrors the existing pre-walk `name` and
## `stateType` capture. When `localIdx == -1` the destructor lookup
## falls back to `preWalkAttachedTypeName`, which keys correctly into
## the `destructorTypes` table and the discard is accepted.
##
## Mirrors the round-6 propagation pattern applied to other
## `LocalTypestate` CONSTRUCTION sites (line ~982 in-place advancement,
## ~1156 var-init binding, ~1789 asgn rebind, ~1305/~1416
## reconcileBranches). This site was a USE site (not a construction
## site), which is why the audit matrix extended in this round had to
## enumerate it explicitly.
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

# Attached holder type. Destructor registers against `Mailbox`, keyed
# under "Mailbox" in destructorTypes (NOT under "Driver").
type Mailbox {.Drive: Driver.} = object
  payload: int

proc `=destroy`(m: var Mailbox) {.destructorTransition.} =
  ## Destructor closes the Mailbox holder. Lookup-key contract:
  ## destructorTypes["Mailbox"] (the attached type name) maps to
  ## typestate `Drive`.
  discard

proc handle(src: sink Driver, m: var Mailbox): Driven {.transition.} =
  ## `m` is an attached param: stateType=Driver (initial),
  ## attachedTypeName=Mailbox. `discard move(m)` triggers the operand
  ## walk's intrinsic block which drops `m` from the live-set. Post-walk
  ## localIdx is -1.
  ##
  ## Pre-round-9: attachedKey forced to "" → destructor lookup missed
  ## the Mailbox-keyed destructor → CFG-003 false-fired even though the
  ## attached holder's destructor bridges to terminal at the moved-out
  ## temporary's scope exit.
  ##
  ## Post-round-9: preWalkAttachedTypeName captures "Mailbox" before the
  ## walk; the lookup keys on it and succeeds → CFG-003 stays silent.
  result = Driven()
  discard move(m)

var box: Mailbox
discard handle(Driver(), box)
verifyTypestates()
echo "cfg_analyzer_discard_attached_type_with_destructor ok"
