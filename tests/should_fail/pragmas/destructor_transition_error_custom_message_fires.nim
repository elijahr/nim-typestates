## Test (v0.9.3 transitionError): a `{.destructorTransition.}` proc declared
## with `transitionError: "custom"` on a transition-validity violation
## (DT-011: DstState not terminal) surfaces the custom message verbatim
## AND fully replaces the built-in `is not a terminal state of typestate`
## diagnostic.
# expects: "Door cannot resolve to Unlocked at destruction"
# rejects: "is not a terminal state of typestate"
import ../../../src/typestates

type
  DoorT = object
  LockedDoor = distinct DoorT
  UnlockedDoor = distinct DoorT
  BrokenDoor = distinct DoorT
  ClosedDoor = distinct DoorT

typestate DoorT:
  consumeOnTransition = false
  strictTransitions = false
  states LockedDoor, UnlockedDoor, BrokenDoor, ClosedDoor
  initial:
    LockedDoor
  terminal:
    BrokenDoor
    ClosedDoor
  transitions:
    LockedDoor -> UnlockedDoor
    UnlockedDoor -> ClosedDoor
    LockedDoor -> BrokenDoor

# DT-011: UnlockedDoor is NOT a terminal state; the spec pins a non-terminal
# destination. With `transitionError:`, the custom message replaces the
# built-in DT-011 diagnostic.
proc `=destroy`(
    d: var LockedDoor
) {.
    destructorTransition: LockedDoor -> UnlockedDoor,
    transitionError: "Door cannot resolve to Unlocked at destruction"
.} =
  discard
