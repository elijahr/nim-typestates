## Test (Round-5 Finding #4, CFG-001 negative — asgn RHS wrapped in
## `nnkPar` parses cleanly through the binding-recovery path): the
## Nim parser wraps single-expression parenthesised RHS in `nnkPar`,
## so `f = (produce(seed))` parses as `nnkAsgn(f, nnkPar(produce(seed)))`.
##
## Pre-round-5: the asgn handler keyed off `rhs.kind in
## {nnkCall, nnkCommand}` directly. `nnkPar` slipped to the else-
## branch which recursed into children (applying nested call
## effects via `walkCfg`) but never invoked the LHS binding-recovery
## path. The result: the analyzer-level rebind to the call's
## destination state was skipped, so the tracked argument `seed` was
## consumed (intrinsic) but `f`'s post-asgn state was incorrect:
## still tracked at its declared SlotActive (terminal) and never
## re-confirmed against the call's destination. For a non-terminal
## destination this would manifest as a state-divergence; for the
## terminal destination here the regression silently masked itself
## because both pre- and post-states were terminal. The wrapper-
## strip fix restores the canonical asgn-rebind path so all
## destinations are validated uniformly.
##
## Post-round-5: the asgn handler strips transparent AST wrappers
## (`nnkPar`, `nnkStmtListExpr`, `nnkBlockStmt`, `nnkBlockExpr`)
## from the RHS before the kind check via the new
## `stripTransparentExprWrappers` helper. The wrapped registered
## transition is recognised, `seed` is sink-consumed, and `f` is
## rebound to the call's destination state.
import ../../../src/typestates

type
  Slot = object
    n: int

  SlotIdle = distinct Slot
  SlotActive = distinct Slot

typestate Slot:
  consumeOnTransition = false
  strictTransitions = false
  states SlotIdle, SlotActive
  initial:
    SlotIdle
  terminal:
    SlotActive
  transitions:
    SlotIdle -> SlotActive

proc produce(s: sink SlotIdle): SlotActive {.transition.} =
  ## Registered transition: SlotIdle -> SlotActive (terminal).
  result = SlotActive(s.Slot)

proc cycle() {.notATransition.} =
  ## Asgn-RHS wrapped in `nnkPar`: `f = (produce(seed))`. Pre-round-5
  ## the parser-injected nnkPar made the asgn handler miss the
  ## registered-transition binding path; `seed` would still be
  ## consumed (the else-branch recursed into children and the nested
  ## call's intrinsic-consume on `seed` still fired), but the LHS
  ## rebind logic was skipped entirely. Post-round-5 the wrapper
  ## strip restores the canonical asgn-rebind path.
  var seed: SlotIdle
  var f: SlotActive
  f = (produce(seed))
  discard f

verifyTypestates()
cycle()
echo "cfg_analyzer_asgn_wrapped_in_parens ok"
