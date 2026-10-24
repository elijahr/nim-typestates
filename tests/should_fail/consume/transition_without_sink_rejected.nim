## Test: consumeOnTransition = true rejects transition taking state by lent borrow (without sink or var).
##
## expects: "requires 'sink' parameter to enforce move semantics"
## expects: "Parameter is passed by lent borrow, allowing use-after-move"

import ../../../src/typestates

type
  Device = object
    id: int

  Off = distinct Device
  On = distinct Device

typestate Device:
  # consumeOnTransition = true is default
  states Off, On
  transitions:
    Off -> On

proc turnOn(d: Off): On {.transition.} =
  On(Device(d))
