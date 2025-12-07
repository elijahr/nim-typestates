## Runner that verifies tconsume_on_transition.nim fails to compile.

import std/[osproc, strutils]

let (output, exitCode) = execCmdEx("nim c --hints:off tests/should_fail/consume/consume_on_transition.nim")

if exitCode == 0:
  echo "FAIL: Compilation should have failed but succeeded"
  quit(1)

if "cannot copy" in output.toLowerAscii or "=copy" in output.toLowerAscii or "is not available" in output.toLowerAscii:
  echo "PASS: Compilation correctly failed with copy error"
else:
  echo "FAIL: Compilation failed but with unexpected error"
  echo output
  quit(1)
