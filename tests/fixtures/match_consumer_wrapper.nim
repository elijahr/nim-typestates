## Layer 2 of the `match_external_consumer` regression test.
##
## Imports the typestate-defining module so the generic proc body can reference
## `match` (the kind enum + match macro are visible HERE because of the
## `import`). This module does NOT re-export `match_consumer_lib`. Mirrors
## `lockfreequeues/mupmuc.nim`: imports the typestate submodule but does not
## re-export it.
import ./match_consumer_lib

# Re-export only the inputs the consumer needs to construct/call. The typestate
# kind enum (`OutcomeKind` with fields `oOk`, `oErr`) is intentionally NOT
# re-exported.
export Payload, Pending, decide

# A generic proc whose body invokes the `match` macro. When the consumer (which
# does not import `match_consumer_lib`) calls `runOutcome[T]`, Nim instantiates
# this body in the consumer's compile context. At that point sema runs over
# the body and expands `match`. Before the v0.7.2 fix the macro emitted bare
# `oOk` / `oErr` idents that needed to resolve at the consumer's call site —
# and failed because the consumer never imported the kind enum.
proc runOutcome*[T](p: sink Pending, okVal: T, errVal: T): T =
  var r = p.decide()
  match r:
    Ok(_):
      result = okVal
    Err(_):
      result = errVal
