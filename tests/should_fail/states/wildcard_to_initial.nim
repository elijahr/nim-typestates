## Test that wildcard transition TO initial state fails.

import ../../../src/typestates

type
  Flow = object
  Start = distinct Flow
  Middle = distinct Flow
  End = distinct Flow

typestate Flow:
  consumeOnTransition = false
  states Start, Middle, End
  initial:
    Start
  transitions:
    Start -> Middle
    Middle -> End
    * ->Start # ERROR: Cannot transition TO initial state
