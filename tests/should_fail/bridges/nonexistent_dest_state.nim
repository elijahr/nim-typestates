## Test: Bridge to non-existent state should fail
## Expected error: State not found or undeclared
import ../../../src/typestates

type
  Auth = object
  Done = distinct Auth

  Session = object
  Active = distinct Session

typestate Session:
  consumeOnTransition = false # Opt out for existing tests
  strictTransitions = false
  states Active

typestate Auth:
  consumeOnTransition = false # Opt out for existing tests
  strictTransitions = false
  states Done
  bridges:
    Done -> Session.NonExistent # NonExistent doesn't exist in Session
