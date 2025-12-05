## Test: Bridge not declared in bridges block should fail
## Expected error: "Undeclared bridge"
import ../../../src/typestates

type
  Source = object
  Ready = distinct Source

  Target = object
  Active = distinct Target

typestate Source:
  strictTransitions = false
  states Ready
  # NO bridges block - bridge not declared

typestate Target:
  strictTransitions = false
  states Active

# This should fail - bridge not declared
proc activate(s: Ready): Active {.transition.} =
  Active(Target())
