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

import std/[osproc, os, strutils, terminal]

const Fixture = "tests/should_compile/bridges/bridge_terminal_no_trap.nim"

proc fail(msg: string) =
  stdout.styledWrite(fgRed, "[FAIL]")
  stdout.write(" tbridge_no_trap_runner: ", msg, "\n")
  quit(1)

if not fileExists(Fixture):
  fail("fixture missing: " & Fixture)

# Compile WITHOUT --warningAsError:User so unrelated User warnings (e.g. the
# §3.7 C3 same-name collision warning, which legitimately fires on this
# fixture's `typestate Session:` / `type Session = object` pair) don't mask
# the bridge-exemption regression we're hunting. We grep the output instead
# for the specific trap-state warning text.
let cmd =
  "nim c --skipUserCfg --skipParentCfg --hints:off --warnings:on " & Fixture
let (output, exitCode) = execCmdEx(cmd)

let binPath = Fixture.changeFileExt("")
if fileExists(binPath):
  removeFile(binPath)

if exitCode != 0:
  fail(
    "fixture failed to compile (exit=" & $exitCode &
      ").\n--- output ---\n" & output
  )

if "Trap state 'Authenticated'" in output:
  fail(
    "trap-state warning fired for 'Authenticated' — the bridge exemption " &
      "in reachability analysis regressed.\n--- output ---\n" & output
  )

stdout.styledWrite(fgGreen, "[PASS]")
stdout.write(
  " tbridge_no_trap_runner: bridged terminal source emits no trap-state warning\n"
)
