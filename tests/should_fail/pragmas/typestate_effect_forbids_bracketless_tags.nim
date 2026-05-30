## Test (Gemini Finding 2 — RED): bracketless `{.tags: SingleTag.}` form
## on a `{.transition.}` proc still injects TypestateOp into the tags
## effect set, so a `{.forbids: [TypestateOp].}` caller MUST refuse to
## compile.
##
## Bug history: pre-fix, the `transition` macro only detected the
## bracketed form of `tags:` (`{.tags: [X].}`) when scanning the
## existing pragma list. The bracketless form (`{.tags: X.}`, no
## `nnkBracket`) slipped past the detector and the macro appended a
## SECOND, duplicate `tags:` pragma. Nim treats only the last `tags:`
## pragma as the proc's effective tag set, so the user's `X` was
## silently dropped AND/OR TypestateOp's propagation through the
## `forbids` system became unreliable.
##
## Under the fix, the macro normalizes the bracketless form into a
## bracket and merges TypestateOp into it idempotently. With the
## injection working correctly, the `{.forbids: [TypestateOp].}`
## region below MUST be rejected by the compiler.
##
## expects: "illegal effect: TypestateOp"
{.experimental: "strictEffects".}
import ../../../src/typestates

type
  MyTag = object of RootEffect

  EndpointBase = object
  Unbound = distinct EndpointBase
  Bound = distinct EndpointBase

typestate Endpoint:
  consumeOnTransition = false
  strictTransitions = false
  states Unbound, Bound
  transitions:
    Unbound -> Bound

# Bracketless single-tag form. Pre-fix: the macro fails to find this as
# an existing `tags:` pragma and appends a duplicate. Post-fix: macro
# merges TypestateOp into the user's bracketless tag list.
proc bareBindIt(u: Unbound): Bound {.transition, tags: MyTag.} =
  Bound(EndpointBase(u))

proc forbidsOp() {.forbids: [TypestateOp].} =
  let u = Unbound(EndpointBase())
  discard bareBindIt(u)

forbidsOp()
