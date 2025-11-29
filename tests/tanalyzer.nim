# This tests the detection of unmarked transitions
# The actual implementation requires module-level analysis
# This is a placeholder test - see src/nim_typestates/analyzer.nim

import ../src/nim_typestates

type
  File = object
  Closed = distinct File
  Open = distinct File

typestate File:
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
