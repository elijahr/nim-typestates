## Runner that verifies initial/terminal state tests fail to compile.

import std/[osproc, strutils]

proc testTransitionToInitial(): bool =
  echo "Testing: transition TO initial state..."
  let (output, exitCode) =
    execCmdEx("nim c --hints:off tests/should_fail/states/transition_to_initial.nim")

  if exitCode == 0:
    echo "  FAIL: Compilation should have failed but succeeded"
    return false

  if "initial state" in output.toLowerAscii or
      "cannot transition to" in output.toLowerAscii or
      "cannot declare transition to" in output.toLowerAscii:
    echo "  PASS: Compilation correctly failed with initial state error"
    return true
  else:
    echo "  FAIL: Compilation failed but with unexpected error"
    echo "  Output: ", output
    return false

proc testTransitionFromTerminal(): bool =
  echo "Testing: transition FROM terminal state..."
  let (output, exitCode) =
    execCmdEx("nim c --hints:off tests/should_fail/states/transition_from_terminal.nim")

  if exitCode == 0:
    echo "  FAIL: Compilation should have failed but succeeded"
    return false

  if "terminal state" in output.toLowerAscii or
      "cannot transition from" in output.toLowerAscii or
      "cannot declare transition from" in output.toLowerAscii:
    echo "  PASS: Compilation correctly failed with terminal state error"
    return true
  else:
    echo "  FAIL: Compilation failed but with unexpected error"
    echo "  Output: ", output
    return false

let test1 = testTransitionToInitial()
let test2 = testTransitionFromTerminal()

if test1 and test2:
  echo "\nAll tests PASSED"
  quit(0)
else:
  echo "\nSome tests FAILED"
  quit(1)
