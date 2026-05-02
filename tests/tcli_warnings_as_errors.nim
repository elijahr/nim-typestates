## End-to-end exit-code matrix for `typestates verify --warnings-as-errors`.
##
## Shells out to the compiled `bin/typestates` binary because the flag is
## parsed in `typestates_bin.nim`, not in the library `verify()` proc.
## Calling `verify()` directly would bypass the flag entirely.
##
## Bin path: per `typestates.nimble:9 binDir = "bin"`, the binary is at
## `./bin/typestates` — NOT `./typestates` as some prose suggested.

import std/[unittest, osproc, strutils, os]

const Bin = "./bin/typestates"

proc runVerify(args: openArray[string]): tuple[exitCode: int, output: string] =
  let cmd = Bin & " verify " & args.join(" ") & " 2>&1"
  let (output, code) = execCmdEx(cmd)
  result = (code, output)

suite "verify --warnings-as-errors":
  setup:
    # Build the binary on demand so this suite is self-contained when run
    # via `nim r tests/...`. `nimble test` already runs `buildCli` first
    # in many setups, but we don't want the suite to depend on that.
    if not fileExists(Bin):
      let (buildOutput, buildCode) = execCmdEx("nimble --useSystemNim buildCli")
      if buildCode != 0:
        echo "BUILD FAILED:"
        echo buildOutput
    check fileExists(Bin)

  test "no flag, no warnings, no errors -> exit 0":
    let (code, _) = runVerify(["tests/fixtures/cli_clean.nim"])
    check code == 0

  test "no flag, with warnings -> exit 0":
    let (code, _) = runVerify(["tests/fixtures/cli_warning_dead.nim"])
    check code == 0

  test "flag, no warnings -> exit 0":
    let (code, _) = runVerify(["--warnings-as-errors", "tests/fixtures/cli_clean.nim"])
    check code == 0

  test "flag, with warnings -> exit 1":
    let (code, _) =
      runVerify(["--warnings-as-errors", "tests/fixtures/cli_warning_dead.nim"])
    check code == 1

  test "flag, with errors and warnings -> exit 1":
    # Stronger than just exit code: the unmarked fixture's StrictDoor produces
    # both an unmarked-proc ERROR and an orphan-state WARNING. Assert both
    # surface in the output so a regression that drops one severity tier
    # (e.g. warning suppression collapses to errors-only) surfaces here.
    let (code, output) =
      runVerify(["--warnings-as-errors", "tests/fixtures/cli_unmarked.nim"])
    check code == 1
    check "ERROR:" in output
    check "Unmarked" in output
    check "WARNING:" in output

  test "no flag, with errors -> exit 1":
    let (code, _) = runVerify(["tests/fixtures/cli_unmarked.nim"])
    check code == 1

  test "-W short alias is equivalent to --warnings-as-errors":
    # docs/guide/ci-integration.md documents `-W` as the short form. Verify
    # the alias is wired through to the same exit-code semantics.
    let (codeWith, _) = runVerify(["-W", "tests/fixtures/cli_warning_dead.nim"])
    check codeWith == 1
    let (codeWithout, _) = runVerify(["-W", "tests/fixtures/cli_clean.nim"])
    check codeWithout == 0
