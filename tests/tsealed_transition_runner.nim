import std/[osproc, strutils]

# First compile the library module
let (out1, code1) = execCmdEx("nim c tests/tsealed_transition/payment.nim")
if code1 != 0:
  echo "FAIL: payment.nim failed to compile"
  echo out1
  quit(1)

# Now try to compile user_code which should fail
let (output, exitCode) = execCmdEx("nim c tests/tsealed_transition/user_code.nim")

if exitCode == 0:
  echo "FAIL: Expected compilation to fail but it succeeded"
  quit(1)

let lowerOutput = output.toLower
if "sealed" in lowerOutput and "transition" in lowerOutput:
  echo "PASS: Compilation correctly failed - cannot add transition to sealed typestate"
else:
  echo "FAIL: Compilation failed but not with expected error"
  echo "Output:"
  echo output
  quit(1)
