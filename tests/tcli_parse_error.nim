## ParseError routing tests: a malformed Nim file under `verify` MUST surface
## as a structured `Finding` (`code = fcParseError`) and route through every
## output formatter — default, github, json — without aborting the pipeline.
##
## Uses the existing `tests/fixtures/syntax_error.nim` (verified to trigger
## ParseError as of main@8ddb25b: `proc broken( =`). If on a future Nim
## version the fixture stops triggering ParseError, that is itself a
## regression worth surfacing — escalate rather than swapping payloads.
##
## ## Implementation note
##
## Nim's compiler `parseAll` calls `quit(1)` from `msgs.handleError` on
## syntax errors by default, which would kill the host process before any
## `try/except ParseError` in `cli.verify()` could fire. `parsePNode` in
## `ast_parser.nim` installs a raising `errorHandler` on the underlying
## `Lexer` after `openParser`; that hook converts the parser's diagnostic
## path into a catchable `ParseError`, which `verify()` turns into an
## `fcParseError` Finding routed through every formatter.

import std/[unittest, osproc, strutils, os]

const Bin = "./bin/typestates"
const BadFile = "tests/fixtures/syntax_error.nim"

proc runVerify(extraArgs: openArray[string]): tuple[exitCode: int, output: string] =
  let cmd = Bin & " verify " & extraArgs.join(" ") & " " & BadFile & " 2>&1"
  let (output, code) = execCmdEx(cmd)
  result = (code, output)

suite "verify ParseError routing":
  setup:
    if not fileExists(Bin):
      let (buildOutput, buildCode) = execCmdEx("nimble --useSystemNim buildCli")
      if buildCode != 0:
        echo "BUILD FAILED:"
        echo buildOutput
    check fileExists(Bin)
    check fileExists(BadFile)

  test "fixture still triggers a syntax error in this Nim version":
    # Regression guard: if a future Nim version starts accepting
    # `proc broken( =` as valid syntax, all the other tests would silently
    # pass against a non-malformed input. This test pins the assumption:
    # the fixture MUST produce a non-zero exit.
    let (code, _) = runVerify([])
    check code != 0

  test "default format: malformed file exits non-zero with error message":
    let (code, output) = runVerify([])
    check code == 1
    let lower = output.toLowerAscii
    check ("parse" in lower) or ("error" in lower) or ("syntax" in lower)

  test "json format: malformed file emits parse-error finding":
    # ParseError is converted to an `fcParseError` Finding inside
    # `verify()` (see `ast_parser.raisingErrorHandler`) and serialized into
    # the JSON envelope's `errors[]`.
    let (code, output) = runVerify(["--format=json"])
    check code == 1
    check "\"code\":\"parse-error\"" in output
    check "\"schemaVersion\":1" in output

  test "github format: malformed file emits ::error annotation":
    # Same routing as the JSON test; the GitHub formatter renders the
    # `fcParseError` Finding as a `::error` workflow command.
    let (code, output) = runVerify(["--format=github"])
    check code == 1
    check "::error" in output
