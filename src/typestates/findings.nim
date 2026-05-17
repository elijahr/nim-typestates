## Structured CLI findings emitted by `typestates verify`.
##
## v0.7 replaces the v0.6 `seq[string]` errors/warnings model with a single
## `seq[Finding]` collection. Findings carry structured fields (path, line,
## severity, code, message, hint) so output formatters can render human,
## GitHub Actions, or JSON output from the same data.

import std/[json, strutils, sequtils]

const SchemaVersion* = 1

type
  Severity* = enum
    sevError = "error"
    sevWarning = "warning"

  FindingCode* = enum
    fcFileNotFound = "file-not-found"
    fcParseError = "parse-error"
    fcUnmarkedProcStrict = "unmarked-proc-strict"
    fcUnmarkedProc = "unmarked-proc"
    fcUnreachableState = "unreachable-state"
    fcNonTerminalState = "non-terminal-state"
    fcOrphanState = "orphan-state"
    fcNoEntryPoint = "no-entry-point"
    fcOpaqueStateBypass = "opaque-state-bypass"
    fcOpaqueStatesNoInitials = "opaque-states-no-initials"

  Finding* = object
    ## Structured CLI finding emitted by `typestates verify`.
    ##
    ## :var path: Source file (`""` if not file-scoped).
    ## :var line: 1-indexed line number; `0` if not applicable.
    ## :var column: 1-indexed column number; `0` if not applicable.
    ## :var severity: Determines exit-code gating.
    ## :var code: Stable wire identifier (see ci-integration.md).
    ## :var message: Single-line summary. No leading whitespace, no newlines.
    ## :var hint: Optional multi-line elaboration. `""` if absent.
    path*: string
    line*: int
    column*: int
    severity*: Severity
    code*: FindingCode
    message*: string
    hint*: string

  VerifyResult* = object
    findings*: seq[Finding]
    transitionsChecked*: int
    filesChecked*: int

proc mkError*(
    code: FindingCode,
    path: string,
    line: int,
    message: string,
    hint: string = "",
    column: int = 0,
): Finding =
  Finding(
    path: path,
    line: line,
    column: column,
    severity: sevError,
    code: code,
    message: message,
    hint: hint,
  )

proc mkWarning*(
    code: FindingCode,
    path: string,
    line: int,
    message: string,
    hint: string = "",
    column: int = 0,
): Finding =
  Finding(
    path: path,
    line: line,
    column: column,
    severity: sevWarning,
    code: code,
    message: message,
    hint: hint,
  )

proc errors*(r: VerifyResult): seq[Finding] =
  r.findings.filterIt(it.severity == sevError)

proc warnings*(r: VerifyResult): seq[Finding] =
  r.findings.filterIt(it.severity == sevWarning)

proc anyErrors*(r: VerifyResult): bool =
  r.findings.anyIt(it.severity == sevError)

proc anyWarnings*(r: VerifyResult): bool =
  r.findings.anyIt(it.severity == sevWarning)

proc parseFindingCode*(s: string): FindingCode =
  ## Parse a stable wire string back into a `FindingCode`. Symmetric with `$`.
  parseEnum[FindingCode](s)

# ---------------------------------------------------------------------------
# Formatters
# ---------------------------------------------------------------------------

proc formatHuman*(f: Finding): string =
  ## Human-readable single- or multi-line rendering. Reproduces v0.6 layout
  ## verbatim: `{path}:{line} - {message}` (or path-only / message-only when
  ## fields are absent), followed by a `\n`-prefixed, two-space-indented hint
  ## block when `f.hint` is non-empty.
  let head =
    if f.path.len > 0 and f.line > 0:
      f.path & ":" & $f.line & " - " & f.message
    elif f.path.len > 0:
      f.path & " - " & f.message
    else:
      f.message
  if f.hint.len == 0:
    head
  else:
    let indented = f.hint.split('\n').mapIt("  " & it).join("\n")
    head & "\n" & indented

proc urlEncodeMessage(s: string): string =
  ## Encodes characters that GitHub Actions workflow commands treat specially
  ## inside the message body: `%`, `\r`, `\n`.
  result = newStringOfCap(s.len)
  for c in s:
    case c
    of '%':
      result.add "%25"
    of '\r':
      result.add "%0D"
    of '\n':
      result.add "%0A"
    else:
      result.add c

proc urlEncodeParam(s: string): string =
  ## Encodes characters that GitHub Actions workflow commands treat
  ## specially inside the `file=...` parameter list. Per the workflow
  ## command spec only `%`, `\r`, `\n`, `,`, and `:` need escaping —
  ## `,` and `:` are the documented parameter separators, the others are
  ## the body-message reserved characters carried over for safety.
  ## Spaces pass through unchanged: encoding them as `%20` made paths
  ## less readable in CI logs without spec benefit (round-3 review fix).
  result = newStringOfCap(s.len)
  for c in s:
    case c
    of '%':
      result.add "%25"
    of '\r':
      result.add "%0D"
    of '\n':
      result.add "%0A"
    of ',':
      result.add "%2C"
    of ':':
      result.add "%3A"
    else:
      result.add c

proc formatGitHub*(f: Finding): string =
  ## GitHub Actions workflow-command annotation. Spec:
  ## https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/workflow-commands-for-github-actions
  ##
  ## `col=` is emitted only when `f.column != 0`, mirroring the `line=`
  ## omission policy: a missing column field would otherwise render as
  ## `col=0`, which the runner would interpret as column 0 rather than
  ## "unspecified".
  let kw = $f.severity # "error" or "warning"
  var params = ""
  if f.path.len > 0:
    params = " file=" & urlEncodeParam(f.path)
    if f.line > 0:
      params.add ",line=" & $f.line
    if f.column > 0:
      params.add ",col=" & $f.column
  let body =
    if f.hint.len == 0:
      urlEncodeMessage(f.message)
    else:
      urlEncodeMessage(f.message & "\n" & f.hint)
  result = "::" & kw & params & "::" & body

proc toJsonNode(f: Finding): JsonNode =
  ## Per-finding JSON shape; severity is implicit in the array name.
  ## Field order: path, line, column, code, message, hint.
  result =
    %*{
      "path": f.path,
      "line": f.line,
      "column": f.column,
      "code": $f.code,
      "message": f.message,
      "hint": f.hint,
    }

proc formatJson*(
    findings: seq[Finding], filesChecked, transitionsChecked: int
): string =
  ## Single-line JSON envelope with `schemaVersion`. Errors and warnings split
  ## into separate arrays; severity is implicit per-array.
  ##
  ## Single-pass partition: walks `findings` once and dispatches each
  ## finding to either the errors or warnings bucket (vs the previous
  ## two-pass `filterIt` + `map` shape, which traversed the input twice
  ## and allocated an intermediate filtered seq each time).
  var errs: seq[JsonNode] = @[]
  var warns: seq[JsonNode] = @[]
  for f in findings:
    case f.severity
    of sevError:
      errs.add f.toJsonNode()
    of sevWarning:
      warns.add f.toJsonNode()
  let envelope =
    %*{
      "schemaVersion": SchemaVersion,
      "verifyResult": {
        "filesChecked": filesChecked,
        "transitionsChecked": transitionsChecked,
        "errors": errs,
        "warnings": warns,
      },
    }
  result = $envelope
