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
# Regression fixture for first-token errors (gemini-code-assist #2 / #8).
# `openParser` reads the first token synchronously inside its body, so the
# error handler MUST be installed on `p.lex.errorHandler` BEFORE calling
# `openParser`. If a future refactor moves the assignment back after
# `openParser`, this fixture will crash the host process via the default
# `msgs.handleError -> quit(1)` path instead of producing a Finding.
const FirstTokBadFile = "tests/fixtures/syntax_error_first_token.nim"

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

  test "default format: malformed file routes ParseError through finding pipeline":
    # Stronger than a generic "contains the word error" — pin the structural
    # contract emitted by `typestates_bin.nim` for the default formatter:
    #   1. an `ERROR: ` line (per-finding, severity-gated prefix)
    #   2. the trailing `N error(s) found` summary (post-loop accounting)
    #   3. the malformed fixture path inside the ERROR line (Nim's parser
    #      diagnostic embeds it; if the routing regressed to a generic
    #      file-not-found code the path would still appear, but the
    #      `(line, col)` shape is parser-specific)
    # A regression that drops the ParseError -> Finding conversion would
    # either crash before the loop (no `error(s) found` summary) or report
    # `All checks passed!` (wrong summary).
    let (code, output) = runVerify([])
    check code == 1
    check "ERROR: " in output
    check BadFile in output
    check "1 error(s) found" in output
    check "All checks passed!" notin output

  test "json format: malformed file emits parse-error finding":
    # ParseError is converted to an `fcParseError` Finding inside
    # `verify()` (see `ast_parser.raisingErrorHandler`) and serialized into
    # the JSON envelope's `errors[]`.
    let (code, output) = runVerify(["--format=json"])
    check code == 1
    check "\"code\":\"parse-error\"" in output
    check "\"schemaVersion\":1" in output

  test "first-token syntax error: handler installed before openParser":
    # Regression guard for gemini-code-assist findings #2 / #8: a syntax
    # error in the very FIRST token must surface as a structured Finding,
    # not crash the host process via the compiler's default `quit(1)`
    # path. Distinct from the mid-file `BadFile` test because
    # `openParser` reads the first token *inside* its body, so any
    # handler installed after `openParser` would never see this error.
    check fileExists(FirstTokBadFile)
    let cmd = Bin & " verify " & FirstTokBadFile & " 2>&1"
    let (output, code) = execCmdEx(cmd)
    check code == 1
    check "ERROR: " in output
    check "1 error(s) found" in output
    check FirstTokBadFile in output

  test "github format: malformed file emits ::error annotation":
    # Same routing as the JSON test; the GitHub formatter renders the
    # `fcParseError` Finding as a `::error` workflow command.
    # Stronger than `"::error" in output`: a generic file-not-found or
    # other-error code would still satisfy that. Pin (a) the workflow-command
    # prefix, (b) the fixture file path inside `file=` (parser diagnostic
    # carries it), and (c) at least one parser-shaped diagnostic token.
    let (code, output) = runVerify(["--format=github"])
    check code == 1
    check "::error" in output
    check "syntax_error.nim" in output
    check ("expected" in output) or ("Error" in output)
