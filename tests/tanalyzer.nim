# This tests the detection of unmarked transitions
# The actual implementation requires module-level analysis
# This is a placeholder test - see src/typestates/analyzer.nim

import ../src/typestates

type
  File = object
  Closed = distinct File
  Open = distinct File

typestate File:
  consumeOnTransition = false  # Opt out for existing tests
  states Closed, Open
  transitions:
    Closed -> Open
    Open -> Closed

# This proc looks like a transition but isn't marked
# With detection enabled, this should warn/error
# TODO: Currently not detected - requires future implementation
proc sneakyOpen(f: Closed): Open =
  result = Open(f)

echo "analyzer test - placeholder (detection not yet implemented)"
