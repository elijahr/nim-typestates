## Test: `{.transition.}` injects the implicit `TypestateOp` effect tag.
##
## Under `{.experimental: "strictEffects".}` the Nim compiler tracks tag
## propagation: a proc tagged `{.tags: [T].}` (directly or via injection)
## propagates `T` to any caller that lacks the tag.  This test exercises
## the positive direction (a region that admits `TypestateOp` calls a
## transition successfully) and pairs with `tests/should_fail/pragmas/
## typestate_effect_forbids.nim` (negative direction: forbidding
## `TypestateOp` rejects a transition call).
##
## Per Task A4 of plans/2026-05-28-static-thread-affinity-impl.md.
{.experimental: "strictEffects".}
import std/unittest
import ../src/typestates

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

# Helper that forwards to the transition. Under strictEffects, if
# `bindIt` carries `TypestateOp` in its tag set then `forwarder` must
# also carry it (transitive propagation).  We assert that by declaring
# `forwarder` with explicit `{.tags: [TypestateOp].}`: if the injection
# did NOT happen, `bindIt` would have an empty tag set and the explicit
# declaration here would still compile (tags are upper bounds); but a
# region that calls `bindIt` from a `{.forbids: [TypestateOp].}` region
# would not trip.  The compile-fail sibling test covers the forbid path
# (the load-bearing assertion); this file verifies the happy-path call
# under an explicitly tagged caller compiles AND runs.
proc forwarder(u: Unbound): Bound {.tags: [TypestateOp, RootEffect].} =
  bindIt(u)

verifyTypestates()

suite "TypestateOp implicit effect injection":
  test "transition proc is callable from a {.tags: [TypestateOp].} region":
    let u = Unbound(EndpointBase())
    let b = forwarder(u)
    # Round-trip the distinct types to compare structurally.
    # EndpointBase is an empty object, so two values are equal iff the
    # conversion path produced an EndpointBase at all.
    check EndpointBase(b) == EndpointBase()

  test "TypestateOp is a RootEffect descendant exported from typestates":
    # Compile-time witness: assigning into a RootEffect-typed slot
    # confirms the inheritance relationship.  Runtime assertion proves
    # the type symbol resolves from the typestates module export.
    var op: TypestateOp
    let r: RootEffect = op
    check r is RootEffect
