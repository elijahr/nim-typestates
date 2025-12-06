## Runner that verifies tsame_base_name.nim fails to compile with correct error.

import std/[osproc, strutils]

let (output, exitCode) = execCmdEx("nim c --hints:off tests/should_fail/states/same_base_name.nim")

if exitCode == 0:
  echo "FAIL: Compilation should have failed but succeeded"
  quit(1)

if "Multiple states share the base name" in output and "distinct wrapper types" in output:
  echo "PASS: Compilation correctly failed with same-base-name error"
  echo "Error message includes guidance on using wrapper types"
else:
  echo "FAIL: Compilation failed but with unexpected error"
  echo output
  quit(1)
