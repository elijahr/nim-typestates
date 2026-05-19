## Test (Round-14 Gemini r13 HIGH — CFG-001 positive: sink-param body
## must consume the sink param). A registered `{.transition.}` proc
## taking `sink T` where `T` is a non-terminal state with no registered
## destructor MUST consume the sink param in its body. Pre-round-14 the
## analyzer skipped `isSink=true` entries at pre-population on the
## theory that the canonical `result = Dst(src.Base)` shape would
## false-fire — but that skip silently passed bodies that constructed
## `result` from a fresh value and never referenced the sink param.
##
## Pattern exercised:
##
##   proc tx(s: sink Open): Closed {.transition.} =
##     result = Closed(File(h: 0))   # `s` never consumed!
##
## Pre-round-14: clean. Post-round-14: CFG-001 fires on `s` at
## fall-through (sink param leaked non-terminal).
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

proc tx(s: sink Open): Closed {.transition.} =
  ## Body never consumes `s`. `result` is built from a fresh `File`
  ## value, leaving the sink param at non-terminal `Open` at
  ## fall-through. Round-14 pre-population now tracks the sink param,
  ## so the exit edge fires CFG-001.
  result = Closed(File(h: 0))

verifyTypestates()
