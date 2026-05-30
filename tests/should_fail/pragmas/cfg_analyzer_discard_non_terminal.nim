## Test (CFG-003 — discard of non-terminal typestate value): a registered
## proc's body declares a typestate-bearing local in a non-terminal state
## with NO registered `{.destructorTransition.}`, then discards it. The
## CFG analyzer must reject the discard at the discard node.
##
## Per §3.3 handleDiscard: when the discarded expression's static type is
## a typestate state that is NOT terminal AND has no covering destructor,
## emit CFG-003.
##
## Static-type resolution: the discard operand is a bare Ident (`discard s`)
## referring to a tracked local. The analyzer's R-6 fallback resolves the
## type via the per-local state map. `getTypeInst` is not consulted here
## because the body AST is captured pre-typecheck at registration time.
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
  ## `s` is bound at Pending (non-terminal, no destructor); the `discard`
  ## fires CFG-003 before fall-through would have fired CFG-001.
  var s: Pending
  discard s
  result = Approved(t)

verifyTypestates()
