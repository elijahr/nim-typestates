## Test that consumeOnTransition = true allows in-place transitions via `var` parameters.

import ../../../src/typestates

type
  Device = object
    id: int
    data: string

  Off = distinct Device
  On = distinct Device

typestate Device:
  # consumeOnTransition = true is default
  states Off, On
  transitions:
    Off -> On

# In-place transition takes `var` parameter
proc turnOnInPlace(d: var Off): On {.transition.} =
  d.Device.data = "active"
  result = On(Device(id: d.Device.id, data: d.Device.data))

var dev = Off(Device(id: 42, data: "init"))
let on = turnOnInPlace(dev)
doAssert on is On

echo "transition_with_var_param ok"
