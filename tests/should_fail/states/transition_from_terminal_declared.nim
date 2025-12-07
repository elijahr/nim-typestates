## Test that declaring transition FROM terminal state fails at DSL level.

import ../../../src/typestates

type
  Flow = object
  Start = distinct Flow
  End = distinct Flow
  AfterEnd = distinct Flow

typestate Flow:
  consumeOnTransition = false
  states Start, End, AfterEnd
  terminal: End
  transitions:
    Start -> End
    End -> AfterEnd  # ERROR: Cannot transition FROM terminal state
