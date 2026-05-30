## Test (DT-006): destructor param type is not a registered typestate state
## and not in the §3.7 attachment registry.
## Expected error: "is not part of any registered typestate"
# expects: "is not part of any registered typestate"
import ../../../src/typestates

type
  Widget = object
    color: int

  WidgetOn = distinct Widget
  WidgetOff = distinct Widget

  # Note: NoTypestate is NOT a state of any registered typestate, and we
  # have not implemented the §3.7 attachment pragma yet (sub-phase 3.1.b.4).
  NoTypestate = object
    foo: int

typestate Widget:
  consumeOnTransition = false
  strictTransitions = false
  states WidgetOn, WidgetOff
  initial:
    WidgetOn
  terminal:
    WidgetOff
  transitions:
    WidgetOn -> WidgetOff

proc `=destroy`(n: var NoTypestate) {.destructorTransition.} =
  discard
