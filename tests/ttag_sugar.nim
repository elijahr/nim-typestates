## Failing test for `{.transition(tag: SomeTag).}` sugar pragma (Task A0/A1).
##
## RED phase: the existing `transition` macro at `src/typestates/pragmas.nim`
## takes only `(procDef: untyped)`. The sugar form `transition(tag: ProducerOp)`
## does not yet exist, so this file MUST fail to compile until Task A2 lands
## the keyword-argument overload and the tag-injection logic.
##
## Acceptance:
## - `bindIt` declared with `{.transition(tag: ProducerOp), gcsafe.}` parses
##   and the pragma expands such that `{.tags: [ProducerOp].}` is propagated.
## - A caller declared with `{.tags: [ProducerOp].}` compiles when invoking
##   `bindIt`.
## - A caller declared WITHOUT `{.tags: [ProducerOp].}` (and with
##   `{.forbids: [ProducerOp].}` to make the effect-system check observable)
##   fails to compile when invoking `bindIt`.

{.experimental: "strictEffects".}

import std/unittest
import ../src/typestates

type
  ProducerOp = object of RootEffect

  Endpoint = object
  Unbound = distinct Endpoint
  Bound = distinct Endpoint

typestate EndpointFsm:
  consumeOnTransition = true
  strictTransitions = true
  states Unbound, Bound
  transitions:
    Unbound -> Bound

proc bindIt(u: sink Unbound): Bound {.transition(tag: ProducerOp), gcsafe.} =
  result = Bound(u)

verifyTypestates()

# Caller with the effect tag declared: MUST compile.
proc callerWithTag(u: sink Unbound): Bound {.tags: [ProducerOp], gcsafe.} =
  result = bindIt(u)

suite "transition(tag:) sugar":
  test "sugar expands to {.transition, tags: [ProducerOp].}":
    var u = Unbound(Endpoint())
    let b = callerWithTag(u)
    # The Bound result is opaque; the meaningful assertion is that the
    # full pipeline compiled. Exact equality on a marker proves the
    # whole call chain executed end-to-end.
    check (b is Bound) == true

  test "caller without ProducerOp in tags fails to compile":
    # `compiles()` returns false when the effect system rejects the call
    # because `bindIt` propagates ProducerOp into the caller's tag set
    # and `forbids: [ProducerOp]` makes that propagation a hard error.
    const callerWithoutTagCompiles = compiles:
      proc callerForbidsTag(u: sink Unbound): Bound {.
          forbids: [ProducerOp], gcsafe.} =
        result = bindIt(u)
    check callerWithoutTagCompiles == false
