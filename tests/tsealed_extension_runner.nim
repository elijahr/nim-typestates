## Test runner for sealed typestate extension.
## Verifies that sealed typestates cannot be extended.

import std/[osproc, strutils]

# Try to compile extension_code which should fail
let (output, exitCode) = execCmdEx("nim c tests/tsealed_extension/extension_code.nim")

if exitCode == 0:
  echo "FAIL: Expected compilation to fail but it succeeded"
  quit(1)

let lowerOutput = output.toLower
if "sealed" in lowerOutput and "extend" in lowerOutput:
  echo "PASS: Compilation correctly failed - cannot extend sealed typestate"
else:
  echo "FAIL: Compilation failed but not with expected error"
  echo "Output:"
  echo output
  quit(1)
