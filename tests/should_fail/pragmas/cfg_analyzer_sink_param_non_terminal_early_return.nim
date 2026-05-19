## Test (Round-14 Gemini r13 HIGH — CFG-001 positive: sink-param body
## early-return before consume). A registered `{.transition.}` proc
## taking `sink T` whose body has an early `return` BEFORE consuming
## the sink param leaks the param at the early-return exit edge.
## Pre-round-14 the pre-population skip suppressed this fire; round-14
## tracks sink params symmetrically with `var T`, so the analyzer now
## reports CFG-001 at the early return.
##
## Pattern exercised:
##
##   proc tx(s: sink Open, cond: bool): Closed {.transition.} =
##     if cond:
##       return Closed(File(h: 0))   # early return, `s` never consumed
##     result = Closed(s.File)       # canonical consume path
##
## Pre-round-14: clean. Post-round-14: CFG-001 fires at the early
## return because `s` is still non-terminal on that exit edge.
# expects: "Open"
# expects: "terminal"
import ../../../src/typestates

type
  File = object
    h: int

  Open = distinct File
  Closed = distinct File

typestate File:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Closed

proc tx(s: sink Open, cond: bool): Closed {.transition.} =
  ## Early-return arm constructs `result` independently of `s`; the
  ## sink param is still non-terminal `Open` at the return statement.
  ## Round-14 fires CFG-001 here. The fall-through arm consumes `s`
  ## canonically and would be clean in isolation.
  if cond:
    return Closed(File(h: 0))
  result = Closed(s.File)

verifyTypestates()
