## TypestateOp implicit effect — runnable example.
##
## The `{.transition.}` macro automatically injects the `TypestateOp`
## effect tag into every transition proc. Under Nim's
## `{.experimental: "strictEffects".}`, this lets a caller statically
## declare a region that MUST NOT contain any typestate transition by
## writing `{.forbids: [TypestateOp].}` on the enclosing proc.
##
## Why this matters:
##
## - **Audit boundaries.** A hot-path proc, an interrupt handler, an
##   `async` callback, or a critical section can statically forbid
##   typestate transitions — guaranteeing none are reachable from
##   inside, even through transitive helper calls. The check is a
##   compile-time effect-system check, zero runtime cost.
## - **Refactor safety.** If a helper proc later starts calling a
##   transition (directly or via a deeper helper), every
##   `{.forbids: [TypestateOp].}` caller that reaches it will fail to
##   compile — catching the regression at the type-system level rather
##   than at runtime.
## - **No opt-in friction.** Transitions get the tag automatically.
##   Callers that don't care about the tag see zero behavior change
##   (outside `strictEffects` Nim performs no propagation at all).
##
## Run with: `nim c -r examples/typestate_op.nim`

{.experimental: "strictEffects".}

import ../src/typestates

type
  Connection = object
    id: int

  # Three connection states. The typestate FSM permits
  # Unbound -> Bound -> Closed (a typical resource lifecycle).
  Unbound = distinct Connection
  Bound = distinct Connection
  Closed = distinct Connection

typestate Connection:
  consumeOnTransition = false
  strictTransitions = false
  states Unbound, Bound, Closed
  transitions:
    Unbound -> Bound
    Bound -> Closed

# A transition. The {.transition.} macro automatically injects
# {.tags: [TypestateOp, RootEffect].} on this proc — no manual effect
# annotation needed.
proc bindIt(u: Unbound): Bound {.transition.} =
  echo "  [transition] bindIt: Unbound -> Bound"
  Bound(Connection(u))

proc closeIt(b: Bound): Closed {.transition.} =
  echo "  [transition] closeIt: Bound -> Closed"
  Closed(Connection(b))

# A driver region that *permits* TypestateOp. Calling `bindIt` and
# `closeIt` (both tagged TypestateOp via injection) is allowed here.
# RootEffect is required because the body also performs `echo` (IO).
proc runLifecycle() {.tags: [TypestateOp, RootEffect].} =
  echo "Driver region (TypestateOp permitted):"
  let u = Unbound(Connection(id: 1))
  let b = bindIt(u)
  let c = closeIt(b)
  echo "  Final state reached: Closed (id=", Connection(c).id, ")"

# A driver region that *forbids* TypestateOp. Any attempt to call a
# transition from inside this proc — directly or via a transitive
# helper — is rejected at compile time.
proc auditedRegion() {.forbids: [TypestateOp], tags: [RootEffect].} =
  echo "Audited region (TypestateOp forbidden):"
  echo "  (this region statically cannot drive transitions)"
  # The following line would fail to compile with:
  #   Error: illegal effect: TypestateOp
  #
  # let u = Unbound(Connection(id: 2))
  # let b = bindIt(u)  # <-- compile error
  echo "  (commented-out bindIt(u) call would not compile here)"

verifyTypestates()

when isMainModule:
  echo "=== TypestateOp Implicit Effect Demo ===\n"

  runLifecycle()
  echo ""
  auditedRegion()

  # Prove the negative case is enforced by `compiles()`: this expression
  # must evaluate to `false` because `bindIt` carries TypestateOp and
  # `auditedRegionBad` forbids it.
  const forbiddenCallRejected = not compiles(
    block:
      proc auditedRegionBad() {.forbids: [TypestateOp], tags: [RootEffect].} =
        let u = Unbound(Connection(id: 99))
        discard bindIt(u)

      auditedRegionBad()
  )
  echo "\nCompile-time check: forbids: [TypestateOp] rejects bindIt() call? ",
    forbiddenCallRejected
  doAssert forbiddenCallRejected,
    "Expected forbids: [TypestateOp] to reject a transition call"

  echo "\n=== Demo complete ==="
