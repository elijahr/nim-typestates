## Test (Round-5 Finding #2, CFG-001 negative — dot-call intrinsic
## `f.move()` / `f.sink()` recognised as consumption): the method-call
## sugar form of the `move` / `sink` intrinsics is parsed as
## `nnkCall(nnkDotExpr(receiver, methodIdent))` — the callee IS the
## DotExpr, and the receiver is the consumed value.
##
## Pre-round-5: `isIntrinsicConsumer` recognised only the bare
## ident/sym form (`move(f)`), SymChoice overloads, and the qualified
## `system.move(f)` form (DotExpr with receiver == "system"). The
## arbitrary-receiver DotExpr shape `f.move()` slipped through the
## recognizer, so library code using pipe-style intrinsic consumption
## left the underlying tracked local on the live-set and false-fired
## CFG-001 at fall-through (or asgn-binding loss for the asgn-RHS
## variant).
##
## Post-round-5: `isIntrinsicConsumer` accepts ANY DotExpr whose
## trailing identifier is `move` or `sink`. A companion helper
## `intrinsicConsumerArg(call)` disambiguates the consumed argument
## position: for `system.move(f)` (qualified prefix) the arg is
## `call[1]`; for `f.move()` (method-call sugar) the arg is the
## receiver `call[0][0]`. Both shapes route through the same
## live-set drop in `applyCallTransitions` and the discard handler.
##
## Note on `sink` symmetry: only `move` is exercised here because
## `f.sink()` does not parse in Nim — `sink` is a reserved type
## modifier, and the parser treats the dot-call form as a type
## expression rather than a method call. The recognizer accepts both
## `move` and `sink` for completeness (qualified `system.sink(f)`
## remains in the existing discard_system_move fixture), but the
## dot-call shape is exercisable only for `move`.
import ../../../src/typestates

type
  Channel = object
    handle: int

  Active = distinct Channel
  Drained = distinct Channel

typestate Channel:
  consumeOnTransition = false
  strictTransitions = false
  states Active, Drained
  initial:
    Active
  terminal:
    Drained
  transitions:
    Active -> Drained

proc drain(a: sink Active): Drained {.transition.} =
  result = Drained(a.Channel)

proc useDotCallMove() {.notATransition.} =
  ## Discard the method-call intrinsic: `discard f.move()` — the
  ## receiver `f` is the consumed value. The analyzer's discard
  ## handler routes the operand through `walkCfg`, which lands in
  ## `applyCallTransitions`. There `intrinsicConsumerArg` recognises
  ## the dot-call shape and drops the underlying tracked local `f`
  ## from the live-set. Fall-through validates with no leftover
  ## non-terminal tracked locals.
  var f: Active
  discard f.move()

proc useDotCallMoveAsgn() {.notATransition.} =
  ## Asgn-RHS variant: `x = f.move()` — `f` (receiver) is consumed,
  ## `x` is the destination local at the same Active state (the move
  ## transfers the value to `x` without changing the value's
  ## typestate). Subsequent `drain(x)` advances `x` to terminal
  ## Drained.
  var f: Active
  var x: Active
  x = f.move()
  discard drain(x)

verifyTypestates()
useDotCallMove()
useDotCallMoveAsgn()
echo "cfg_analyzer_dot_call_intrinsic_move ok"
