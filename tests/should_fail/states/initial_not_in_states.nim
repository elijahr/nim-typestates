## Test that initial state must be in states list.

import ../../../src/typestates

type
  Flow = object
  Start = distinct Flow
  End = distinct Flow
  NotDeclared = distinct Flow

typestate Flow:
  consumeOnTransition = false
  states Start, End
  initial:
    NotDeclared # ERROR: NotDeclared is not in states list
  transitions:
    Start -> End
