# expects: "Duplicate event declaration 'TurnOn'"
## Error: Declaring an event twice in the events block must fail compile-time validation.

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
    TurnOn
  transitions:
    Off on TurnOn -> On
