## Runner for ttype_mismatch.nim compile-fail test.
##
## Verifies that Nim's type checker catches return type mismatches
## even when the transition pragma passes validation.

import std/[osproc, strutils]

let (output, exitCode) =
  execCmdEx("nim c --path:src tests/ttype_mismatch/mismatch_code.nim 2>&1")

if exitCode == 0:
  echo "FAIL: Expected compilation to fail but it succeeded"
  quit(1)

let lowerOutput = output.toLower

# Check for type mismatch error - Nim should catch that we're returning
# Closed when Open is expected
if "type mismatch" in lowerOutput or "cannot convert" in lowerOutput or
    "got 'closed'" in lowerOutput:
  echo "PASS: Nim correctly catches type mismatch in transition implementation"
  echo ""
  echo "This demonstrates that:"
  echo "  1. The {.transition.} pragma validates the declared transition"
  echo "  2. Nim's type system enforces the actual return type"
  echo "  3. You cannot accidentally return the wrong state type"
else:
  echo "FAIL: Compilation failed but not with expected type mismatch error"
  echo "Output:"
  echo output
  quit(1)
