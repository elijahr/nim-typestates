# expects: "Undeclared event 'UnknownEvent' in transition"
## Error: Referencing an undeclared event in a transition must fail compile-time validation.

import ../../../src/typestates

type
  Device = object
  Off = distinct Device
  On = distinct Device

typestate Device:
  consumeOnTransition = false
  states Off, On
  events:
    TurnOn
  transitions:
    Off on UnknownEvent -> On
