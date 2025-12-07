## Runner for all edge case tests.
##
## Tests both positive cases (should compile) and negative cases (should fail).

import std/[osproc, strutils]

var passed = 0
var failed = 0

proc shouldCompile(name, path: string) =
  let (output, exitCode) = execCmdEx("nim c --hints:off " & path)
  if exitCode == 0:
    echo "  PASS: ", name
    inc passed
  else:
    echo "  FAIL: ", name, " (should compile but failed)"
    echo output
    inc failed

proc shouldFail(name, path, expectedError: string) =
  let (output, exitCode) = execCmdEx("nim c --hints:off " & path)
  if exitCode != 0 and expectedError in output:
    echo "  PASS: ", name
    inc passed
  elif exitCode == 0:
    echo "  FAIL: ", name, " (compiled but should have failed)"
    inc failed
  else:
    echo "  FAIL: ", name, " (failed but with wrong error)"
    echo "  Expected: ", expectedError
    echo output
    inc failed

echo "=== Positive Edge Cases (should compile) ==="
shouldCompile("consumeOnTransition with generics", "tests/tedge_cases_consume.nim")
shouldCompile("initial/terminal edge cases", "tests/tedge_cases_initial_terminal.nim")
shouldCompile("multiline states edge cases", "tests/tedge_cases_multiline.nim")

echo ""
echo "=== Negative Edge Cases (should fail) ==="
shouldFail("wildcard to initial state",
           "tests/should_fail/states/wildcard_to_initial.nim",
           "initial state")
shouldFail("transition from terminal (declared)",
           "tests/should_fail/states/transition_from_terminal_declared.nim",
           "terminal state")
shouldFail("initial not in states list",
           "tests/should_fail/states/initial_not_in_states.nim",
           "not in states list")
shouldFail("terminal not in states list",
           "tests/should_fail/states/terminal_not_in_states.nim",
           "not in states list")

echo ""
echo "=== Results ==="
echo "Passed: ", passed
echo "Failed: ", failed

if failed > 0:
  quit(1)
else:
  echo "All edge case tests passed!"
