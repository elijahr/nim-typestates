import std/[osproc, strutils]

let (output, exitCode) = execCmdEx("nim c tests/ttransition_validation/invalid_code.nim")

if exitCode == 0:
  echo "FAIL: Expected compilation to fail but it succeeded"
  quit(1)

let lowerOutput = output.toLower
if "undeclared transition" in lowerOutput or "not a valid" in lowerOutput or "open -> locked" in lowerOutput:
  echo "PASS: Compilation correctly failed with transition validation error"
  echo "Error message found in output"
else:
  echo "FAIL: Compilation failed but not with expected error"
  echo "Output:"
  echo output
  quit(1)
