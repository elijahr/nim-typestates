# expects: "Expected `name: Type` in event parameters"
## Error: Malformed event parameter without a type must fail compile-time validation.

import ../../../src/typestates

type
  Device = object
  Off = distinct Device
  On = distinct Device

typestate Device:
  consumeOnTransition = false
  states Off, On
  events:
    TurnOn(invalidParamNoType)
  transitions:
    Off on TurnOn -> On
