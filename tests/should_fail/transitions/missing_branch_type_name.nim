## Expected error: "Branching transitions require a result type name"
## Branching transitions must use the 'as TypeName' syntax.

import ../../../src/typestates

type
  Request = object
  Pending = distinct Request
  Success = distinct Request
  Failure = distinct Request

typestate Request:
  consumeOnTransition = false  # Opt out for existing tests
  states Pending, Success, Failure
  transitions:
    Pending -> Success | Failure  # ERROR: Missing 'as TypeName'
