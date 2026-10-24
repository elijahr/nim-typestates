## Test: strictEvents = true compiles successfully when all non-terminal states handle all events.

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
    Idle on Reset -> Idle
    Active on Start -> Active
    Active on Reset -> Done

echo "strict_events_exhaustive ok"
