## Test (Round-12 Gemini r11 finding #1, CFG-001 positive — multi-
## typestate-param call site leaves a trailing typestate-bearing
## arg at a non-terminal tracked state): the round-12 per-arg
## consumption loop iterates the matched transition's
## `typestatedParams`. For trailing non-sink typestate-bearing params
## the analyzer applies the conservative "drop from tracking" rule
## (the registration captures one return type but no per-param dst,
## so any non-sink trailing param's post-call state is structurally
## underspecified).
##
## This fixture exercises a sink-trailing scenario where the SINK
## consumption IS correctly applied to both args, but the bound LHS
## return result is non-terminal AND has no destructor — so CFG-001
## fires on the LHS leak. It locks in that the multi-param consumption
## path correctly handles the call's args without masking downstream
## terminal-state validation.
# expects: "has not reached a terminal state"
# expects: "SlotContext"
import ../../../src/typestates

type
  Slot = object
    n: int

  Open = distinct Slot
  Pending = distinct Slot
  Intermediate = distinct Slot
  Closed = distinct Slot

typestate SlotContext:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Pending, Intermediate, Closed
  initial:
    Open
    Pending
  terminal:
    Closed
  transitions:
    Open -> Intermediate
    Pending -> Intermediate
    Open -> Closed
    Pending -> Closed
    Intermediate -> Closed

proc combine(a: sink Open, b: sink Pending): Intermediate {.transition.} =
  ## Multi-typestate-param sink consumer registered as
  ## (Open, Pending) -> Intermediate. Both args sink-consumed.
  ## Intermediate is non-terminal, so the call-site LHS binding must
  ## be carried to a terminal-producing consumer or fail CFG-001 at
  ## fall-through.
  result = Intermediate(a.Slot)

proc drive(a: var Open, b: var Pending): Intermediate {.transition.} =
  ## Both params are `var T` so round-2 pre-populates them. The call
  ## `combine(a, b)`:
  ##   1. Round-12 fix consumes BOTH `a` and `b` via the matched
  ##      transition's typestatedParams loop.
  ##   2. The LHS binds as Intermediate (non-terminal).
  ##   3. No downstream consumer is called — `result` is left at
  ##      Intermediate (non-terminal, no destructor registered).
  ##   4. Fall-through exit edge fires CFG-001 on the unbound result.
  result = combine(a, b)

verifyTypestates()
