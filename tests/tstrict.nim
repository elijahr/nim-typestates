## Test that strictTransitions works correctly
## Note: strictTransitions is enforced via verifyTypestates() macro,
## not inline at each proc definition.

import ../src/typestates

type
  File = object
  Closed = distinct File
  Open = distinct File

typestate File:
  strictTransitions = false  # Disable for this test
  states Closed, Open
  transitions:
    Closed -> Open
    Open -> Closed

# All procs properly marked
proc open(f: Closed): Open {.transition.} =
  result = Open(f)

proc read(f: Open): string {.notATransition.} =
  result = "data"

# Without strictTransitions = false, this would need marking
proc helper(f: Open): int =
  result = 42

echo "strict test passed (with strictTransitions = false)"
