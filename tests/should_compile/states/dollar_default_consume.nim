## F3: `$` codegen exercised under DEFAULT `consumeOnTransition = true`.
##
## The other dollar fixtures (`dollar_overload`, `dollar_generic`,
## `dollar_branching_*`) override `consumeOnTransition = false`, so they do
## NOT prove the `$` overload survives the lifecycle hooks (`=copy` blocked,
## sink-only transitions) that the default mode adds.
##
## This fixture intentionally does NOT override the flag. It exercises:
##   1. `$theStateEnum` — the enum-side `$` overload (no value-read involved).
##      This is the only form that is safe under default consume rules
##      because it never reads (and therefore never copies/moves) a state
##      VALUE.
##   2. `$value` at a value's LAST use — Nim's move semantics let the
##      by-value `$` overload consume the value cleanly without invoking the
##      blocked `=copy` hook.
##
## Note on the documented `$state(value)` workaround: under default consume
## rules, `state(value)` itself takes its parameter by-value (no `sink`),
## which moves the value. That makes `$state(value)` followed by further use
## of the value impossible — the value is gone after the call. This fixture
## therefore exercises `$state(value)` only at last-use sites, matching what
## the F3 docs actually allow under default settings.
import ../../../src/typestates

type
  Door = object
    id: int

  Closed = distinct Door
  Open = distinct Door
  Locked = distinct Door

typestate Door:
  # consumeOnTransition defaults to true — DO NOT override.
  states Closed, Open, Locked
  transitions:
    Closed -> Open
    Open -> Locked

proc unlock(d: sink Closed): Open {.transition.} =
  Open(Door(d))

proc lock(d: sink Open): Locked {.transition.} =
  Locked(Door(d))

# (1) Enum-side `$` overload — no value read, immune to consume rules.
#     This is the safest form under default consume and is exercised at
#     module scope.
doAssert $fsClosed == "Closed"
doAssert $fsOpen == "Open"
doAssert $fsLocked == "Locked"

# Move semantics for the per-state `$` overload only kick in inside a
# proc body where Nim can prove the read is the LAST read of the value.
# (At top-level / module scope, all `let` bindings are observable
# globals, so move-elision does not apply and Nim demands `=copy`,
# which is blocked by `consumeOnTransition = true`.)
proc exerciseDollar() =
  # (2) `$value` at last-use — Nim's move semantics let the by-value
  #     `$` overload consume the value without invoking the blocked
  #     `=copy` hook.
  let c = Closed(Door(id: 1))
  doAssert $c == "Closed" # last read of `c`

  # (3) `$state(value)` at last-use — equivalent shape, exercising the
  #     state() codegen path in addition to the per-state `$` overload.
  let c2 = Closed(Door(id: 2))
  doAssert $state(c2) == "Closed" # last read of `c2`

  # Round-trip a fresh value through a transition, then dollar-print at
  # the end of its lifetime to prove the per-state `$` overload also
  # works on the transition's destination type under default consume.
  let start = Closed(Door(id: 3))
  let opened = start.unlock()
  let locked = opened.lock()
  doAssert $locked == "Locked"

exerciseDollar()

echo "dollar_default_consume test passed"
