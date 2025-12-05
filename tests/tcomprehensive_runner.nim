## Comprehensive test runner for should_fail and should_compile tests.
##
## Discovers all test files in:
## - tests/should_fail/**/*.nim - must NOT compile
## - tests/should_compile/**/*.nim - must compile AND run

import std/[osproc, strutils, os, sequtils, terminal]

type
  TestResult = object
    name: string
    passed: bool
    output: string
    category: string

var results: seq[TestResult] = @[]
var totalPassed = 0
var totalFailed = 0

proc runShouldFailTest(path: string): TestResult =
  ## Test that a file fails to compile
  let name = path.extractFilename.changeFileExt("")
  let category = path.parentDir.extractFilename
  let cmd = "nim c --skipUserCfg --skipParentCfg --hints:off " & path
  let (output, exitCode) = execCmdEx(cmd)

  result.name = category & "/" & name
  result.category = "should_fail"
  result.output = output

  if exitCode != 0:
    result.passed = true
  else:
    result.passed = false
    result.output = "ERROR: File compiled successfully but should have failed"

proc runShouldCompileTest(path: string): TestResult =
  ## Test that a file compiles and runs successfully
  let name = path.extractFilename.changeFileExt("")
  let category = path.parentDir.extractFilename
  let binPath = path.changeFileExt("")

  # Compile
  let compileCmd = "nim c --skipUserCfg --skipParentCfg --hints:off -o:" & binPath & " " & path
  let (compileOutput, compileExit) = execCmdEx(compileCmd)

  result.name = category & "/" & name
  result.category = "should_compile"

  if compileExit != 0:
    result.passed = false
    result.output = "COMPILE ERROR:\n" & compileOutput
    return

  # Run
  let (runOutput, runExit) = execCmdEx(binPath)

  # Cleanup binary
  removeFile(binPath)

  if runExit != 0:
    result.passed = false
    result.output = "RUNTIME ERROR:\n" & runOutput
  else:
    result.passed = true
    result.output = runOutput

proc discoverTests(dir: string): seq[string] =
  ## Find all .nim files recursively
  result = @[]
  if not dirExists(dir):
    return
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".nim"):
      result.add(path)
    elif kind == pcDir:
      result.add(discoverTests(path))

proc printResult(r: TestResult) =
  let status = if r.passed: "[PASS]" else: "[FAIL]"
  let color = if r.passed: fgGreen else: fgRed

  stdout.styledWrite(color, status)
  stdout.write(" ", r.category, ": ", r.name, "\n")

  if not r.passed:
    echo "  ", r.output.indent(2).replace("\n  \n", "\n")

# Main
echo "=== Comprehensive Test Suite ==="
echo ""

# Run should_fail tests
echo "--- Should Fail Tests ---"
let shouldFailTests = discoverTests("tests/should_fail")
for path in shouldFailTests:
  let result = runShouldFailTest(path)
  results.add(result)
  printResult(result)
  if result.passed:
    inc totalPassed
  else:
    inc totalFailed

echo ""

# Run should_compile tests
echo "--- Should Compile Tests ---"
let shouldCompileTests = discoverTests("tests/should_compile")
for path in shouldCompileTests:
  let result = runShouldCompileTest(path)
  results.add(result)
  printResult(result)
  if result.passed:
    inc totalPassed
  else:
    inc totalFailed

echo ""
echo "=== Summary ==="
echo "Passed: ", totalPassed
echo "Failed: ", totalFailed
echo "Total:  ", totalPassed + totalFailed

if totalFailed > 0:
  quit(1)
else:
  echo "All tests passed!"
