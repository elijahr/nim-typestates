import ../src/typestates

# Define Session typestate
type
  Session = object
    userId: string
  Active = distinct Session
  Guest = distinct Session

typestate Session:
  states Active, Guest
  transitions:
    Active -> Guest

# Define AuthFlow typestate with bridges
type
  AuthFlow = object
    userId: string
  Pending = distinct AuthFlow
  Authenticated = distinct AuthFlow
  Failed = distinct AuthFlow

typestate AuthFlow:
  states Pending, Authenticated, Failed
  transitions:
    Pending -> Authenticated | Failed as AuthResult
  bridges:
    Authenticated -> Session.Active
    Failed -> Session.Guest

# Valid bridge - should compile
proc startSession(auth: Authenticated): Active {.transition.} =
  result = Active(Session(userId: auth.AuthFlow.userId))

# Valid bridge with branching - should compile
proc handleFailure(auth: Failed): Guest {.transition.} =
  result = Guest(Session(userId: "anonymous"))

echo "Bridge validation test passed"
