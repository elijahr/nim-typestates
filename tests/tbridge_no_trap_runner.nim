## Verifies that `tests/should_compile/bridges/bridge_terminal_no_trap.nim`
## emits ZERO macro warnings.
##
## The original fixture already runs under the comprehensive runner, but the
## comprehensive runner does not enforce per-fixture compile flags, so a
## regression that started flagging the bridged source as a trap state would
## go unnoticed (the warning would appear, the fixture would still compile,
## the test would still PASS — a green-mirage failure mode).
##
## This runner re-compiles the fixture with `--warningAsError:User`. Any
## `User` warning (which is what `macros.warning` emits) becomes a hard
## error. If the `bridges:` exemption regresses, this test goes red.

import std/[osproc, os, terminal]

const Fixture = "tests/should_compile/bridges/bridge_terminal_no_trap.nim"

proc fail(msg: string) =
  stdout.styledWrite(fgRed, "[FAIL]")
  stdout.write(" tbridge_no_trap_runner: ", msg, "\n")
  quit(1)

if not fileExists(Fixture):
  fail("fixture missing: " & Fixture)

let cmd =
  "nim c --skipUserCfg --skipParentCfg --hints:off --warnings:on " &
  "--warningAsError:User " & Fixture
let (output, exitCode) = execCmdEx(cmd)

let binPath = Fixture.changeFileExt("")
if fileExists(binPath):
  removeFile(binPath)

if exitCode != 0:
  fail(
    "fixture compiled with --warningAsError:User produced exit=" & $exitCode &
      " (expected 0). A User warning was emitted, which means a " &
      "macro `warning(...)` fired — most likely the bridge exemption in " &
      "reachability analysis regressed.\n--- output ---\n" & output
  )

stdout.styledWrite(fgGreen, "[PASS]")
stdout.write(
  " tbridge_no_trap_runner: bridged terminal source emits no User warnings\n"
)
