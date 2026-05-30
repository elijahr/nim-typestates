## Test (Round-5 Finding #4, CFG-001 negative — asgn RHS wrapped in
## `nnkBlockStmt` parses cleanly through the binding-recovery path):
## the Nim parser wraps `block: ...; expr` RHS in `nnkBlockStmt`, so
## `f = (block: produce(seed))` parses with the block as the
## top-level RHS child.
##
## Pre-round-5: the asgn handler keyed off `rhs.kind in
## {nnkCall, nnkCommand}` directly. `nnkBlockStmt` slipped to the
## else-branch which recursed into children (applying nested call
## effects via `walkCfg`) but never invoked the LHS binding-recovery
## path. Same symptom as the parens variant: `seed` still consumed
## via nested-call recursion, but `f`'s rebind to the call's
## destination state was skipped.
##
## Post-round-5: the asgn handler strips transparent AST wrappers
## (`nnkPar`, `nnkStmtListExpr`, `nnkBlockStmt`, `nnkBlockExpr`)
## from the RHS before the kind check via the new
## `stripTransparentExprWrappers` helper. The block's body is
## descended to its last expression (the call), the wrapped
## registered transition is recognised, and `f` is rebound to the
## call's destination state.
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
  ## Asgn-RHS wrapped in `nnkBlockStmt`: `f = block: produce(seed)`.
  ## The block-as-expression form is a single-line idiom for
  ## inlining a small setup before the value-producing expression
  ## (here trivially the call alone — the test focuses on the AST
  ## shape, not the use-case). Post-round-5 the wrapper strip
  ## restores the canonical asgn-rebind path; `seed` is consumed,
  ## `f` is rebound to SlotActive.
  var seed: SlotIdle
  var f: SlotActive
  f = block:
    produce(seed)
  discard f

verifyTypestates()
cycle()
echo "cfg_analyzer_asgn_wrapped_in_block ok"
