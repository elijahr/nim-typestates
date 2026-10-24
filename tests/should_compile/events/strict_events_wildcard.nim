## Test: strictEvents = true satisfies event accounting via wildcard transitions.

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
  terminal:
    Done
  events:
    Start
    Reset
  transitions:
    Idle on Start -> Active
    Active on Start -> Active
    *on Reset -> Idle

echo "strict_events_wildcard ok"
