## Comprehensive test runner for should_fail and should_compile tests.
##
## Discovers all test files in:
## - tests/should_fail/**/*.nim - must NOT compile
## - tests/should_compile/**/*.nim - must compile AND run

import std/[osproc, strutils, os, terminal]

type TestResult = object
  name: string
  passed: bool
  output: string
  category: string

var results: seq[TestResult] = @[]
var totalPassed = 0
var totalFailed = 0

proc parseExpectsDirectives(path: string): seq[string] =
  ## Parse `# expects: "<substring>"` directives from a test source file.
  ##
  ## Each directive must appear on its own line (after optional whitespace),
  ## starting with `#`, then `expects:`, then a double-quoted substring.
  ## Lines that do not match are ignored.
  ##
  ## :param path: Absolute or relative path to the .nim test file
  ## :returns: List of substrings expected to appear in the compiler output
  result = @[]
  for rawLine in lines(path):
    let line = rawLine.strip()
    if not line.startsWith("#"):
      continue
    let body = line[1 ..^ 1].strip()
    if not body.startsWith("expects:"):
      continue
    let after = body["expects:".len ..^ 1].strip()
    # Require at least one character between the quotes: `# expects: ""` is
    # rejected so an empty body cannot silently match every compiler output.
    if after.len <= 2 or after[0] != '"' or after[^1] != '"':
      continue
    result.add(after[1 ..^ 2])

proc runShouldFailTest(path: string): TestResult =
  ## Test that a file fails to compile.
  ##
  ## When `# expects: "..."` directives are present in the source file,
  ## each quoted substring must also appear in the captured compiler
  ## output, otherwise the test fails with a diff-style report.
  let name = path.extractFilename.changeFileExt("")
  let category = path.parentDir.extractFilename
  let cmd = "nim c --skipUserCfg --skipParentCfg --hints:off " & path
  let (output, exitCode) = execCmdEx(cmd)

  result.name = category & "/" & name
  result.category = "should_fail"
  result.output = output

  if exitCode == 0:
    result.passed = false
    result.output = "ERROR: File compiled successfully but should have failed"
    return

  let expects = parseExpectsDirectives(path)
  for substr in expects:
    if substr notin output:
      result.passed = false
      result.output =
        "ERROR: expected substring not found in compiler output: " & substr.escape &
        "\n--- compiler output ---\n" & output
      return

  result.passed = true

proc runShouldCompileTest(path: string): TestResult =
  ## Test that a file compiles and runs successfully
  let name = path.extractFilename.changeFileExt("")
  let category = path.parentDir.extractFilename
  let binPath = path.changeFileExt("")

  # Compile
  let compileCmd =
    "nim c --skipUserCfg --skipParentCfg --hints:off -o:" & binPath & " " & path
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
