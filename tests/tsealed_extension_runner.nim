import std/[osproc, strutils]

let (output, exitCode) = execCmdEx("nim c tests/tsealed_extension.nim")

if exitCode == 0:
  echo "FAIL: Expected compilation to fail but it succeeded"
  quit(1)

let lowerOutput = output.toLower
# Must contain "sealed typestate" or "cannot extend sealed" - the actual error message
# Not just any occurrence of "sealed" (which could be in the file path)
if "sealed typestate" in lowerOutput or "cannot extend sealed" in lowerOutput:
  echo "PASS: Compilation correctly failed - sealed typestate cannot be extended"
else:
  echo "FAIL: Compilation failed but not with expected 'sealed typestate' error"
  echo "Output:"
  echo output
  quit(1)
