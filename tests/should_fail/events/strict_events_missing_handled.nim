## Test: strictEvents = true rejects typestates with missing (state, event) transitions.
##
## expects: "Total Event Accounting violation"
## expects: "State 'Idle' does not handle event 'Reset'"

import ../../../src/typestates

type
  Device = object
  Idle = distinct Device
  Active = distinct Device
  Done = distinct Device

typestate Device:
  consumeOnTransition = false
  strictEvents = true
  states Idle, Active, Done
  terminal: Done
  events:
    Start
    Reset
  transitions:
    Idle on Start -> Active
    Active on Reset -> Idle
    Active on Start -> Active
