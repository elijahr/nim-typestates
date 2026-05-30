## Test: Calling a `{.transition.}` proc from a `{.forbids: [TypestateOp].}`
## region must NOT compile under `{.experimental: "strictEffects".}`.
##
## This is the load-bearing assertion for Task A4: it proves that the
## `transition` macro actually injects `TypestateOp` into the proc's
## `tags:` effect set.  If the injection were missing, `bindIt`'s tag
## set would be empty and `badRegion` would compile cleanly — making
## the entire `{.forbids: [TypestateOp].}` opt-in feature a no-op.
##
## expects: "TypestateOp"
{.experimental: "strictEffects".}
import ../../../src/typestates

type
  EndpointBase = object
  Unbound = distinct EndpointBase
  Bound = distinct EndpointBase

typestate Endpoint:
  consumeOnTransition = false
  strictTransitions = false
  states Unbound, Bound
  transitions:
    Unbound -> Bound

proc bindIt(u: Unbound): Bound {.transition.} =
  Bound(EndpointBase(u))

proc badRegion() {.forbids: [TypestateOp].} =
  let u = Unbound(EndpointBase())
  discard bindIt(u)

badRegion()
