## Test (Round-9 Finding #2, CFG-003 positive — discard of an attached
## object-typed local consumed by an intrinsic wrapper, with NO
## destructor registered): when no `{.destructorTransition.}` is
## registered against either the OBJECT type or the typestate STATE
## name, `discard move(m)` of an attached local in a non-terminal state
## MUST fire CFG-003 — the moved-out temporary dies in a non-terminal
## state with no destructor to bridge to terminal.
##
## Validates the round-9 fix does not over-correct: with no destructor
## registered under either key, both lookup paths
## (`preWalkAttachedTypeName` and `exprStateName`) miss, so CFG-003
## still fires correctly. The pre-walk attached-type capture only
## RECOVERS the correct key for lookup — it does not invent a
## destructor where none exists.
# expects: "discard"
# expects: "is not allowed"
# expects: "Driver"
# expects: "not a terminal state"
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

# Attached holder type. NO destructor is registered against Mailbox
# (intentional). Pre-round-9 the discard handler missed the holder-key
# lookup ANYWAY (attachedKey was "") and erroneously made the same
# decision as this fixture's no-destructor case via a different path —
# but as a result, the positive test
# (`cfg_analyzer_discard_attached_type_with_destructor.nim`) would
# false-fire. This negative test confirms that the round-9 lookup-key
# fix does not weaken CFG-003 coverage when no destructor is registered.
type Mailbox {.Drive: Driver.} = object
  payload: int

proc handle(src: sink Driver, m: var Mailbox): Driven {.transition.} =
  ## `m` is an attached param: stateType=Driver, attachedTypeName=
  ## Mailbox. `discard move(m)` triggers the operand walk's intrinsic
  ## block which drops `m` from the live-set. Post-walk localIdx=-1.
  ##
  ## Round-9 lookup: attachedKey = preWalkAttachedTypeName = "Mailbox".
  ## "Mailbox" not in destructorTypes. exprStateName = "Driver" also
  ## not in destructorTypes (no destructorTransition registered). Both
  ## lookup paths miss → hasDestructor=false → CFG-003 fires
  ## correctly.
  result = Driven()
  discard move(m)

verifyTypestates()
