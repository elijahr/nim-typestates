## Test (DT-009): two-arg destructorTransition with malformed spec.
## Expected error: "spec must be of the form `SrcState -> DstState`"
# expects: "spec must be of the form"
import ../../../src/typestates

type
  Holder = object
  H1 = distinct Holder
  H2 = distinct Holder

typestate Holder:
  consumeOnTransition = false
  strictTransitions = false
  states H1, H2
  initial:
    H1
  terminal:
    H2
  transitions:
    H1 -> H2

# Wrong: spec uses `=>` instead of `->`.
proc `=destroy`(h: var H1) {.destructorTransition: H1 => H2.} =
  discard
