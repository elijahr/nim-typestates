## Test (CFG-001 positive — §3.7 attached local, NO destructor): a
## registered transition's body declares an attached-object local,
## never consumes it, and falls through to proc end. Because no
## `{.destructorTransition.}` covers the attached object, CFG-001
## must fire at fall-through.
##
## This fixture is the round-6 regression test for findings #1, #2,
## and #3 — pre-fix the analyzer either dropped attached locals from
## tracking entirely (the var-init binding-recovery path bailed when
## the declared type was the attached object name, not a state) or
## false-passed them (destructor lookup keyed on `stateType` rather
## than `attachedTypeName`).
##
## Why the leaking declaration is inside a registered transition: the
## CFG analyzer's per-proc body walk runs only on procs registered
## via `{.transition.}` / `{.destructorTransition.}`. An unmarked
## proc would never be walked, so a leak in its body would not fire
## CFG-001 — the fixture would compile clean for the wrong reason.
# expects: "has not reached a terminal state"
# expects: "DoorOpen"
# expects: "DoorContext"
import ../../../src/typestates

type
  DoorBase = object
    handle: int

  DoorOpen = distinct DoorBase
  DoorClosed = distinct DoorBase

typestate DoorContext:
  consumeOnTransition = false
  strictTransitions = false
  states DoorOpen, DoorClosed
  initial:
    DoorOpen
  terminal:
    DoorClosed
  transitions:
    DoorOpen -> DoorClosed

# Attach the holder type. NO `{.destructorTransition.}` is registered
# against `Door` — so the analyzer must NOT find a covering destructor
# under either the attached type name `Door` or the resolved state
# name `DoorOpen`.
type Door {.DoorContext: DoorOpen.} = object
  payload: int

# Drive a non-attached source state into terminal so we have a real
# `{.transition.}` whose body the CFG analyzer will walk. This is the
# proc that LEAKS the attached `Door` local.
proc consumeAndLeak(src: sink DoorOpen): DoorClosed {.transition.} =
  ## `src` is consumed naturally by the result construction. But `d`
  ## is an attached local declared inside the body; round-6 fix
  ## tracks `d` with stateType=DoorOpen, attachedTypeName=Door. No
  ## destructor is registered against either key, so the
  ## fall-through exit edge fires CFG-001 naming `d`.
  result = DoorClosed(src.DoorBase)
  var d {.used.}: Door # tracked attached local; leaks at fall-through.

verifyTypestates()
