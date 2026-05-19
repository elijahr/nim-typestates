## Test (Round-5 Finding #3, CFG-003 positive — discard-move-intrinsic
## of a non-terminal local with no destructor): `discard move(f)` is a
## valid Nim ownership-transfer pattern, but if `f`'s type is at a
## non-terminal typestate AND no `{.destructorTransition.}` covers it,
## the discarded moved-out temporary's value dies in a non-terminal
## state — a typestate-protocol violation that CFG-003 forbids.
##
## Pre-round-5: the discard handler short-circuited on intrinsic-callee
## consumption (`isIntrinsicConsumer(opnd[0])`) BEFORE running the
## CFG-003 non-terminal-discard check, so any `discard move(f)`
## silently passed even when `f` was non-terminal with no destructor.
## The short-circuit was also redundant — the operand recursion
## through `walkCfg` -> `applyCallTransitions` already handled the
## intrinsic consumption via its own intrinsic-consumer block.
##
## Post-round-5: the short-circuit is removed. The discard handler
## captures the underlying tracked local's PRE-walk state (via
## `extractTrackedLocal(opnd)` against the entry live-set), then
## walks the operand (which drops `f` from tracking via
## `applyCallTransitions`'s intrinsic block). The CFG-003 check then
## fires against the captured pre-walk state — non-terminal + no
## destructor = error.
# expects: "discard"
# expects: "is not allowed"
# expects: "Pending"
# expects: "not a terminal state"
import ../../../src/typestates

type
  Token = object
    n: int

  Pending = distinct Token
  Approved = distinct Token

typestate Token:
  consumeOnTransition = false
  strictTransitions = false
  states Pending, Approved
  initial:
    Pending
  terminal:
    Approved
  transitions:
    Pending -> Approved

proc handle(t: sink Pending): Approved {.transition.} =
  ## Body declares `f: Pending` (non-terminal, no destructor on
  ## Pending). `discard move(f)` is the intrinsic-consumption shape
  ## that pre-round-5 bypassed CFG-003.
  var f: Pending
  discard move(f)
  result = Approved(t.Token)

verifyTypestates()
