## Runner that compiles tests/should_warn/**/*.nim and asserts each
## `# expects: "<substring>"` directive is present in the COMPILER STDERR/STDOUT.
##
## Each fixture must compile successfully (exit 0) AND emit each expected
## substring in stderr/stdout combined.
##
## Mirrors the directive parser used in tcomprehensive_runner.nim.

import std/[osproc, strutils, os, terminal]

proc parseExpectsDirectives(path: string): seq[string] =
  ## Parse `# expects: "<substring>"` directives from a fixture source.
  result = @[]
  for rawLine in lines(path):
    let line = rawLine.strip()
    if not line.startsWith("#"):
      continue
    let body = line[1 ..^ 1].strip()
    if not body.startsWith("expects:"):
      continue
    let after = body["expects:".len ..^ 1].strip()
    if after.len <= 2 or after[0] != '"' or after[^1] != '"':
      continue
    result.add(after[1 ..^ 2])

proc discoverTests(dir: string): seq[string] =
  result = @[]
  if not dirExists(dir):
    return
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".nim"):
      result.add(path)
    elif kind == pcDir:
      result.add(discoverTests(path))

var totalPassed = 0
var totalFailed = 0

let tests = discoverTests("tests/should_warn")
echo "=== Should Warn Tests ==="
if tests.len == 0:
  stdout.styledWrite(fgRed, "[FAIL]")
  stdout.write(
    " should_warn: discovery returned 0 fixtures (expected at least one). " &
    "Did the directory move or get cleared? Refusing to report a vacuous PASS.\n"
  )
  quit(2)
for path in tests:
  let cmd = "nim c --skipUserCfg --skipParentCfg --hints:off --warnings:on " & path
  let (output, exitCode) = execCmdEx(cmd)
  let name = path.extractFilename.changeFileExt("")
  let expects = parseExpectsDirectives(path)
  var passed = exitCode == 0
  if not passed:
    stdout.styledWrite(fgRed, "[FAIL]")
    stdout.write(" should_warn/", name, ": compilation failed (expected success)\n")
    echo "  Compiler output:\n", output.indent(4)
  else:
    var missing: seq[string] = @[]
    for substr in expects:
      if substr notin output:
        missing.add(substr)
    if missing.len > 0:
      passed = false
      stdout.styledWrite(fgRed, "[FAIL]")
      stdout.write(" should_warn/", name, ": missing expected substrings:\n")
      for m in missing:
        echo "  - ", m.escape
      echo "  Compiler output:\n", output.indent(4)
    else:
      stdout.styledWrite(fgGreen, "[PASS]")
      stdout.write(" should_warn/", name, "\n")
  # Cleanup compiled binary if present
  let binPath = path.changeFileExt("")
  if fileExists(binPath):
    removeFile(binPath)
  if passed:
    inc totalPassed
  else:
    inc totalFailed

echo "\n=== should_warn Summary ==="
echo "Passed: ", totalPassed
echo "Failed: ", totalFailed

if totalFailed > 0:
  quit(1)
