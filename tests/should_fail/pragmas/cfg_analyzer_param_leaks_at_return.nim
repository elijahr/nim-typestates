## Test (CFG-001 positive — typestated `var T` param NOT consumed before
## return, round-2 Finding #2): a registered transition proc takes
## `var f: Open` and returns early without consuming `f`. Under the new
## pre-population the analyzer registers `f` at proc entry; the `return`
## exit edge fires CFG-001 naming the leaked param.
##
## This is the canonical Finding #2 failure mode that the prior analyzer
## silently missed. Pre-Round-2, `LiveState` was initialized empty at
## proc entry, so the early-return path had nothing to validate; the
## proc compiled clean despite leaving the caller's `var` binding in a
## non-terminal, non-destructor-covered state.
##
## The proc is registered via the `tick` `{.transition.}` overload so
## it enters the analyzer's per-proc walk; the `var f: Open` param is
## the body-side typestated local that pre-population captures.
# expects: "has not reached a terminal state at this return"
# expects: "Open"
# expects: "Closed"
import ../../../src/typestates

type
  File = object
    fd: int

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

proc tick(seed: sink Open, f: var Open, skip: bool): Closed {.transition.} =
  ## `f: var Open` is the Finding #2 target — pre-populated into the
  ## live-set at proc entry. The `return` exit edge happens before `f`
  ## is consumed, so CFG-001 fires naming the leaked param `f`.
  result = Closed(seed.File)
  if skip:
    return # CFG-001: 'f' is still Open here.
  # Outside the conditional, f would need a consume; this path is dead.

verifyTypestates()
