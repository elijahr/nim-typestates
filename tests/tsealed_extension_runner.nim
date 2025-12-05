## Test runner for duplicate typestate definition.
## Verifies that typestates cannot be defined twice.

import std/[osproc, strutils]

# Try to compile extension_code which should fail (typestate already defined)
let (output, exitCode) = execCmdEx("nim c tests/tsealed_extension/extension_code.nim")

if exitCode == 0:
  echo "FAIL: Expected compilation to fail but it succeeded"
  quit(1)

let lowerOutput = output.toLower
if "already defined" in lowerOutput:
  echo "PASS: Compilation correctly failed - typestate already defined"
else:
  echo "FAIL: Compilation failed but not with expected error"
  echo "Output:"
  echo output
  quit(1)
