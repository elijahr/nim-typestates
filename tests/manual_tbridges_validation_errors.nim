# This test should fail to compile with specific error messages
# Run manually to verify error messages are correct

import ../src/typestates

type
  Session = object
  Active = distinct Session

typestate Session:
  states Active
  transitions:
    Active -> Active

type
  AuthFlow = object
  Authenticated = distinct AuthFlow

typestate AuthFlow:
  states Authenticated
  transitions:
    Authenticated -> Authenticated
  # Note: No bridges declared

# This should error: bridge not declared
proc startSession(auth: Authenticated): Active {.transition.} =
  result = Active(Session())
