## Verifies the `--define:typestatesNoReachabilityWarn` gate.
##
## Compiles `tests/should_warn/reachability_trap.nim` twice:
##   1) Without the flag — must emit the trap-state warning substrings.
##   2) With  `-d:typestatesNoReachabilityWarn` — the same fixture must
##      compile silently (no `Trap state` warnings).
##
## This guards against the gate being removed or inverted: if either
## invariant breaks, the runner exits non-zero with diagnostics.

import std/[osproc, strutils, os, terminal]

const Fixture = "tests/should_warn/reachability_trap.nim"
const ExpectedWhenOn =
  ["Trap state 'Loop1'", "Trap state 'Loop2'", "cannot reach any terminal state"]
const ForbiddenWhenOff = ["Trap state '"]

proc compile(extraDefines: string): tuple[output: string, exitCode: int] =
  let cmd =
    "nim c --skipUserCfg --skipParentCfg --hints:off --warnings:on " & extraDefines & " " &
    Fixture
  result = execCmdEx(cmd)
  let binPath = Fixture.changeFileExt("")
  if fileExists(binPath):
    removeFile(binPath)

proc fail(msg: string) =
  stdout.styledWrite(fgRed, "[FAIL]")
  stdout.write(" treachability_flag_runner: ", msg, "\n")
  quit(1)

if not fileExists(Fixture):
  fail("fixture missing: " & Fixture)

block warning_on_when_flag_absent:
  let (output, exitCode) = compile("")
  if exitCode != 0:
    fail(
      "compile (no flag) failed unexpectedly. exit=" & $exitCode & "\n--- output ---\n" &
        output
    )
  for substr in ExpectedWhenOn:
    if substr notin output:
      fail(
        "without flag: expected substring missing from compiler output: " & substr.escape &
          "\n--- output ---\n" & output
      )
  stdout.styledWrite(fgGreen, "[PASS]")
  stdout.write(" treachability_flag_runner: warnings emitted by default\n")

block warning_off_when_flag_set:
  let (output, exitCode) = compile("-d:typestatesNoReachabilityWarn")
  if exitCode != 0:
    fail(
      "compile (with -d:typestatesNoReachabilityWarn) failed unexpectedly. " & "exit=" &
        $exitCode & "\n--- output ---\n" & output
    )
  for substr in ForbiddenWhenOff:
    if substr in output:
      fail(
        "with flag: forbidden substring still present in compiler output: " &
          substr.escape & "\n--- output ---\n" & output
      )
  stdout.styledWrite(fgGreen, "[PASS]")
  stdout.write(
    " treachability_flag_runner: warnings silenced by " &
      "-d:typestatesNoReachabilityWarn\n"
  )
