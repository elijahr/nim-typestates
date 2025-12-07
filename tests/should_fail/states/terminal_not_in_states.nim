## Test that terminal state must be in states list.

import ../../../src/typestates

type
  Flow = object
  Start = distinct Flow
  End = distinct Flow
  NotDeclared = distinct Flow

typestate Flow:
  consumeOnTransition = false
  states Start, End
  terminal: NotDeclared  # ERROR: NotDeclared is not in states list
  transitions:
    Start -> End
