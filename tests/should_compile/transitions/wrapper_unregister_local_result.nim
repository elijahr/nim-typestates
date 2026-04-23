## Test: `unregisterTransparentWrapper("Result")` opts out of the built-in
## unwrap so a local typestate state literally named `Result` is validated
## as the destination state, not as a wrapper around some inner type.
##
## Note: this test deliberately does NOT `import results`. Importing the
## results package while simultaneously defining a local type named
## `Result` produces a name-shadowing collision that is unrelated to the
## opt-out semantics. The opt-out behavior is proven by ensuring the
## transition compiles even though `Result` IS in the built-in wrapper
## registry at session start — and the semantics only hold because the
## `static: unregisterTransparentWrapper("Result")` call fires BEFORE the
## {.transition.} proc is processed.
import ../../../src/typestates

static:
  unregisterTransparentWrapper("Result")
  doAssert not isTransparentWrapper("Result"),
    "unregisterTransparentWrapper failed to mutate the registry"

type
  Flow = object
    step: int

  Pending = distinct Flow
  Result = distinct Flow

typestate Flow:
  consumeOnTransition = false
  strictTransitions = false
  states Pending, Result
  transitions:
    Pending -> Result

proc finish(p: Pending): Result {.transition.} =
  Result(Flow(p))

let p = Pending(Flow(step: 1))
let r = p.finish()
doAssert r is Result
echo "wrapper_unregister_local_result test passed"

# Without `static: unregisterTransparentWrapper("Result")` at the top of
# this file, `Result` would still be in the built-in transparent-wrapper
# registry. Then the `Result` in the return type of `finish` would be
# treated as a wrapper head; `extractAllTypeNames` would try to recurse
# into its generic argument. Because this local `Result` is a
# non-generic `distinct Flow`, the AST is a bare nnkIdent (not an
# nnkBracketExpr), so the wrapper unwrap would skip it anyway — meaning
# this file would "accidentally" compile even without the unregister.
# The unregister call makes the opt-out semantics EXPLICIT for readers
# and covers the future case where a local `Result` is itself generic.
