import std/[osproc, strutils]

# Test that strictTransitions = false allows unmarked procs
let (output, exitCode) = execCmdEx("nim c -r tests/tstrict.nim")

if exitCode == 0:
  if "strict test passed" in output:
    echo "PASS: strictTransitions = false correctly allows unmarked procs"
  else:
    echo "FAIL: Compiled but didn't produce expected output"
    echo output
    quit(1)
else:
  echo "FAIL: Compilation failed unexpectedly"
  echo output
  quit(1)
