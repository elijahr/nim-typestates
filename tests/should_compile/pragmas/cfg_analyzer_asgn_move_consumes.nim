## Test (CFG-001 negative — `x = move(f)` intrinsic-callee in asgn,
## round-3 Finding #3, verify.nim:447): when a registered tracked local
## `f` is moved out by an asgn whose RHS is `move(f)`, `f` is consumed
## from tracking. The LHS `x` is a typestate-bearing local of a state
## type COMPATIBLE with `f`'s current state (same distinct), so the
## move is well-typed.
##
## The analyzer-relevant behaviour: post-asgn, `f` is no longer
## accessible (consumed by `move`), so the analyzer drops it from
## tracking. `x` was the destination but the analyzer does not synthesise
## a new state binding for the LHS in the intrinsic-callee path — the
## value's typestate is whatever the RHS produced, and the existing
## binding-recovery (var-init / asgn-from-transition) covers the
## registered-transition cases. Here `x` was declared with the same state
## type, so its existing live-set entry stays valid.
##
## Pre-fix the asgn handler invoked `applyCallTransitions` on
## `move(f)`, which left `f` tracked (move was not a registered
## transition). Post-fix the intrinsic-consumer recognition drops the
## underlying local before the registered-transition lookup.
import ../../../src/typestates

type
  Token = object
    n: int

  Pending = distinct Token
  Spent = distinct Token

typestate Token:
  consumeOnTransition = false
  strictTransitions = false
  states Pending, Spent
  initial:
    Pending
  terminal:
    Spent
  transitions:
    Pending -> Spent

proc spend(t: sink Pending): Spent {.transition.} =
  result = Spent(t.Token)

proc useAsgnMove() {.notATransition.} =
  ## `x` is bound to Pending. `x = move(f)` moves `f` into `x`. The
  ## analyzer drops `f` from tracking; `x` remains at Pending (the
  ## intrinsic-callee asgn doesn't change LHS state). Subsequent
  ## `discard spend(x)` consumes x to terminal Spent.
  var f: Pending
  var x: Pending
  x = move(f)
  discard spend(x)

verifyTypestates()
useAsgnMove()
echo "cfg_analyzer_asgn_move_consumes ok"
