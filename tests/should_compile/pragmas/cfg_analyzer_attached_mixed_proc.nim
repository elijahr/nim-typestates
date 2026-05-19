## Test (positive): proc taking BOTH a state-typed `var` param AND an
## attached-object `var` param. Validates that `hasDestructorFor`'s
## non-attached fallback path (path (a), the pre-round-6 behavior)
## still hits registered destructors keyed on the state name, while
## the new path (b) covers the attached param via its
## `attachedTypeName`.
##
## Pepper's first engineering-judgment note (round-6 brief): "Verify
## hasDestructorFor non-attached fallback still hits existing
## destructors". This fixture is the explicit lock-in for that
## guarantee — both branches of the destructor-lookup-key contract
## must succeed within a single proc body.
import ../../../src/typestates

# Typestate A — STATE-TYPED param consumes via destructor on its
# state. Tests path (a) (non-attached fallback).
type
  LightOn = object
  LightOff = object

typestate Light:
  consumeOnTransition = false
  strictTransitions = false
  states LightOn, LightOff
  initial:
    LightOn
  terminal:
    LightOff
  transitions:
    LightOn -> LightOff

proc `=destroy`(l: var LightOn) {.destructorTransition.} =
  discard

# Typestate B — ATTACHED-OBJECT param consumes via destructor on its
# holder type. Tests path (b).
type
  CamReady = object
  CamShutdown = object

typestate Camera:
  consumeOnTransition = false
  strictTransitions = false
  states CamReady, CamShutdown
  initial:
    CamReady
  terminal:
    CamShutdown
  transitions:
    CamReady -> CamShutdown

type CameraSession {.Camera: CamReady.} = object
  payload: int

proc `=destroy`(c: var CameraSession) {.destructorTransition.} =
  discard

proc operate(l: var LightOn, c: var CameraSession) =
  ## Mixed proc: both params survive only because their respective
  ## destructors fire at fall-through. The analyzer must:
  ##
  ## 1. Pre-pop `l` with stateType=LightOn, attachedTypeName="".
  ## 2. Pre-pop `c` with stateType=CamReady, attachedTypeName=
  ##    CameraSession.
  ## 3. At fall-through: hasDestructorFor(l) returns true via path
  ##    (a) — destructorTypes[LightOn] hits.
  ## 4. At fall-through: hasDestructorFor(c) returns true via path
  ##    (b) — destructorTypes[CameraSession] hits, because
  ##    attachedTypeName="CameraSession" is non-empty.
  discard l
  discard c.payload

verifyTypestates()
echo "cfg_analyzer_attached_mixed_proc ok"
