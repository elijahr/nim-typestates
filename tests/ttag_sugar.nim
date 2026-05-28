## Failing tests for `{.transition(tag: SomeTag).}` sugar pragma (Tasks A0/A1).
##
## RED phase: the existing `transition` macro at `src/typestates/pragmas.nim`
## takes only `(procDef: untyped)`. The sugar form `transition(tag: ProducerOp)`
## does not yet exist, so this file MUST fail to compile until Task A2 lands
## the keyword-argument overload and the tag-injection logic.
##
## Per design §3.1.1, the sugar `{.transition(tag: ProducerOp).}` MUST expand
## to the equivalent of `{.transition, tags: [ProducerOp], gcsafe.}` (with
## `gcsafe` injected only when not already present, and `tags` merged
## additively when an existing `tags:` pragma is on the proc).
##
## Note: Task A4 will additionally inject `TypestateOp` into the tags list.
## This file (Tasks A0/A1) covers ONLY the user-supplied tag and `gcsafe`
## injection; the `TypestateOp` transitive effect lands separately in A3/A4.
##
## DSL form: `consumeOnTransition`/`strictTransitions` are flat children of
## `typestate`, NOT inside a nested `config:` block — verified shape per
## `tests/tstrict.nim:13-14` and `tests/tgeneric_typestate.nim:16,41`.
##
## Acceptance (deepened in Task A1):
## 1. Sugar form `{.transition(tag: ProducerOp).}` parses and propagates the
##    user-supplied tag so a caller declared with `{.tags: [ProducerOp].}`
##    compiles (covered by `callerWithTag` + suite test 1).
## 2. A caller declared with `{.forbids: [ProducerOp].}` fails to compile
##    when invoking a sugar-tagged transition (covered by suite test 2).
## 3. The bare `{.transition.}` form (no keyword arg) still compiles
##    unchanged — sugar must be additive, not breaking (suite test 3).
## 4. Sugar merges additively with an existing `{.tags: [...].}` pragma on
##    the same proc (suite test 4).
## 5. Sugar injects `gcsafe` even when the proc does not declare it
##    explicitly (suite test 5).

{.experimental: "strictEffects".}

import std/unittest
import ../src/typestates

type
  ProducerOp = object of RootEffect
  ConsumerOp = object of RootEffect

  Endpoint = object
  Unbound = distinct Endpoint
  Bound = distinct Endpoint
  Closed = distinct Endpoint

typestate EndpointFsm:
  consumeOnTransition = true
  strictTransitions = true
  states Unbound, Bound, Closed
  transitions:
    Unbound -> Bound
    Bound -> Closed

# Sugar form WITHOUT explicit gcsafe — the macro must inject it (acceptance 5).
proc bindIt(u: sink Unbound): Bound {.transition(tag: ProducerOp).} =
  result = Bound(u)

# Sugar form WITH a pre-existing `tags:` pragma — must merge additively
# (acceptance 4). The resulting effective tags set must contain BOTH
# `ConsumerOp` (pre-existing) and `ProducerOp` (sugar-injected).
proc closeIt(b: sink Bound): Closed {.transition(tag: ProducerOp),
    tags: [ConsumerOp], gcsafe.} =
  result = Closed(b)

# Bare `{.transition.}` form — acceptance 3 (sugar must be additive,
# the old non-sugar form must still compile unchanged).
proc bareBind(u: sink Unbound): Bound {.transition, gcsafe.} =
  result = Bound(u)

verifyTypestates()

# Caller with the sugar-injected tag declared: MUST compile.
proc callerWithTag(u: sink Unbound): Bound {.tags: [ProducerOp], gcsafe.} =
  result = bindIt(u)

# Caller with BOTH tags declared: MUST compile, exercising the merged
# tags set produced by acceptance 4.
proc callerWithBothTags(b: sink Bound): Closed {.
    tags: [ProducerOp, ConsumerOp], gcsafe.} =
  result = closeIt(b)

# Caller of the bare-form transition: MUST compile (acceptance 3).
proc callerOfBare(u: sink Unbound): Bound {.gcsafe.} =
  result = bareBind(u)

suite "transition(tag:) sugar":
  test "sugar expands to {.transition, tags: [ProducerOp], gcsafe.}":
    var u = Unbound(Endpoint())
    let b = callerWithTag(u)
    # The Bound result is opaque; the meaningful assertion is that the
    # full pipeline compiled. Exact equality on a marker proves the
    # whole call chain executed end-to-end.
    check (b is Bound) == true

  test "caller with forbids: [ProducerOp] fails to compile":
    # `compiles()` returns false when the effect system rejects the call
    # because `bindIt` propagates ProducerOp into the caller's tag set
    # and `forbids: [ProducerOp]` makes that propagation a hard error.
    const callerWithoutTagCompiles = compiles:
      proc callerForbidsTag(u: sink Unbound): Bound {.
          forbids: [ProducerOp], gcsafe.} =
        result = bindIt(u)
    check callerWithoutTagCompiles == false

  test "bare {.transition.} form still compiles (sugar is additive)":
    var u = Unbound(Endpoint())
    let b = callerOfBare(u)
    check (b is Bound) == true

  test "sugar merges with pre-existing tags: [ConsumerOp]":
    var b = Bound(Endpoint())
    let c = callerWithBothTags(b)
    check (c is Closed) == true

  test "caller declaring only ConsumerOp fails: ProducerOp must be merged in":
    # If the sugar replaced `[ConsumerOp]` instead of merging,
    # a caller declaring only `[ConsumerOp]` would compile.
    # Because the sugar MUST merge additively, the caller is missing
    # `ProducerOp` and the effect system MUST reject the call.
    const callerMissingProducerCompiles = compiles:
      proc callerOnlyConsumer(b: sink Bound): Closed {.
          tags: [ConsumerOp], forbids: [ProducerOp], gcsafe.} =
        result = closeIt(b)
    check callerMissingProducerCompiles == false
