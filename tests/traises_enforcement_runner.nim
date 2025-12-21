## Test runner for raises enforcement.
## Verifies that transitions must have {.raises: [].}.

import std/[osproc, strutils]

# Test 1: Explicit non-empty raises list should fail
block explicitRaisesTest:
  let (output, exitCode) =
    execCmdEx("nim c tests/traises_enforcement/explicit_raises.nim")

  if exitCode == 0:
    echo "FAIL: Expected compilation to fail for explicit raises"
    quit(1)

  let lowerOutput = output.toLower
  if "non-empty raises" in lowerOutput or "raises: []" in lowerOutput or
      "error state" in lowerOutput:
    echo "PASS: Explicit non-empty raises list correctly rejected"
  else:
    echo "FAIL: Compilation failed but not with expected error"
    echo "Output:"
    echo output
    quit(1)

# Test 2: Implicit raises (calling raising proc) should fail
block implicitRaisesTest:
  let (output, exitCode) =
    execCmdEx("nim c tests/traises_enforcement/implicit_raises.nim")

  if exitCode == 0:
    echo "FAIL: Expected compilation to fail for implicit raises"
    quit(1)

  let lowerOutput = output.toLower
  # The compiler should catch that readFile can raise when we've added raises: []
  if "ioerror" in lowerOutput or "can raise" in lowerOutput or "raises" in lowerOutput:
    echo "PASS: Implicit raises (calling raising proc) correctly rejected"
  else:
    echo "FAIL: Compilation failed but not with expected error"
    echo "Output:"
    echo output
    quit(1)

echo "All raises enforcement tests passed!"
