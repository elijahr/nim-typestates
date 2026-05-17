## Test (DT-002): destructorTransition on a proc that is NOT =destroy.
## Expected error: applies only to `=destroy` hook
# expects: "may only be applied to a `=destroy` hook"
import ../../../src/typestates

type
  Box = object
  Full = distinct Box
  Empty = distinct Box

typestate Box:
  consumeOnTransition = false
  strictTransitions = false
  states Full, Empty
  initial:
    Full
  terminal:
    Empty
  transitions:
    Full -> Empty

# Wrong: destructorTransition on a regular proc, not =destroy.
proc consume(f: var Full) {.destructorTransition.} =
  discard
