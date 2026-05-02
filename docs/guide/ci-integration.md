# CI Integration

`typestates verify` is the entry point for non-interactive validation of a
project tree. It is the same checker the macro side relies on for
reachability and opaque-state cast detection, exposed as a command-line tool
suitable for pre-commit hooks and continuous integration. This guide covers
setup recipes for common CI environments and the contract of the v0.7
machine-readable output formats.

## Overview

`typestates verify <path>` walks every `.nim` file under `<path>`, parses the
typestate declarations and `{.transition.}` procs, and emits findings for:

- Strict-mode violations (procs that should be marked `{.transition.}` or
  `{.notATransition.}` but are not).
- Reachability problems (unreachable states, non-terminal dead ends, orphan
  states with no incoming edges, typestates with no entry point).
- Cast bypass attempts on typestates declared `opaqueStates = true`.
- Configuration warnings (e.g. `opaqueStates = true` without `initial:`).
- Parse errors on malformed `.nim` files.

The exit code is `0` if no errors fired and `1` if any error was emitted.
Warnings do not affect exit by default; use `--warnings-as-errors` to gate
on them.

## Behavior on parse errors

Each input file is parsed independently. If one file fails to parse (for
example, because a contributor pushed an unfinished change), it produces a
single `parse-error` finding for that path and verification continues with
the rest of the batch. A run can therefore surface multiple `parse-error`
findings alongside lint findings from successfully-parsed files. Earlier
versions of `typestates verify` aborted the entire run on the first parse
failure; that behavior changed in v0.7 so a single broken file no longer
masks the rest of the project's results in CI.

## Pre-commit hook

The repo ships a `.pre-commit-hooks.yaml` manifest at its root. Consumers
add an entry to their own `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/elijahr/nim-typestates
    rev: v0.7.0
    hooks:
      - id: typestates-verify
```

The hook runs `typestates verify` against the repository root every time
`pre-commit run` is invoked. It uses `language: system` and assumes
`typestates` is already on PATH. Install with `nimble install typestates`
on each developer machine (or in your CI image).

The hook deliberately uses `pass_filenames: false` and `always_run: true`.
Cast-protection lint requires the typestate definition to be in the verified
path tree; if pre-commit forwarded only the changed consumer files, the
lint would silently no-op when the typestate module was not in the change
set. Running over the project root sidesteps that.

## GitHub Actions

A minimal workflow that installs the package and runs verification:

```yaml
name: typestates

on:
  pull_request:
  push:
    branches: [main]

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jiro4989/setup-nim-action@v2
        with:
          nim-version: '2.2.8'
      - run: nimble install -y typestates
      - run: typestates verify --warnings-as-errors src/
```

For inline annotations on PR diffs, use `--format=github` (see below).

Cache `nimbledeps/` with `actions/cache@v4` keyed on the lockfile if
your workflow installs additional dependencies; `typestates` itself
installs quickly enough that caching it specifically is rarely worth
the cache-key churn.

## GitLab CI

The equivalent `.gitlab-ci.yml` job:

```yaml
typestates:
  image: nimlang/nim:2.2.8
  script:
    - nimble install -y typestates
    - typestates verify --warnings-as-errors src/
```

For pipelines that need machine-readable output, route `--format=json`
to a job artifact and consume it from a downstream job.

## Treating warnings as errors

Pass `--warnings-as-errors` (or `-W`) to `typestates verify`:

```bash
typestates verify --warnings-as-errors src/
```

When set, any warning-severity finding promotes the exit code to `1`.
Findings continue to be labeled "warning" in human and JSON output
(matching the convention of `gcc -Werror` and `clang -Werror`); the
flag changes the exit-code policy, not the rendered severity.

For older `typestates` versions without `--warnings-as-errors`, a portable
fallback uses `grep`:

```bash
typestates verify src/ | tee verify.log
if grep -q 'WARNING' verify.log; then exit 1; fi
```

The `grep` fallback is brittle against output-format changes; prefer
`--warnings-as-errors` whenever the installed version supports it.

## Inline annotations

`--format=github` emits one annotation line per finding using GitHub
Actions' annotation format:

```
::warning file=src/payment.nim,line=42::Captured(payment) outside transition
::error file=src/order.nim,line=17::Undeclared transition: Open -> Closed
::error file=src/parse_me.nim,line=8,col=14::expected closing ')'
```

When run inside a GitHub Actions job, the runner parses these lines
and posts file-and-line annotations directly on the PR diff view.
`col=N` is appended after `line=N` when a column is available
(currently parse errors only); it pins the annotation to the exact
caret position on the diff. Hints (the secondary explanatory text on
reachability findings) are joined to the message with `%0A`-encoded
newlines, which GitHub renders as line breaks in the annotation body.

Stdout under `--format=github` contains only annotation lines. The
"Checked N files" summary routes to stderr so it does not pollute the
annotation parser. Default-format output is unchanged from v0.6.

## JSON output

`--format=json` emits a stable, documented schema suitable for
downstream tooling.

### Schema

Top-level envelope:

```json
{
  "schemaVersion": 1,
  "verifyResult": {
    "filesChecked": 42,
    "transitionsChecked": 17,
    "errors": [],
    "warnings": []
  }
}
```

Each finding inside `errors[]` or `warnings[]` has the shape:

```json
{
  "path": "src/payment.nim",
  "line": 42,
  "column": 17,
  "code": "opaque-state-bypass",
  "message": "Captured(payment) outside any {.transition.} proc",
  "hint": ""
}
```

### Field semantics

| Field | Type | Meaning |
|---|---|---|
| `schemaVersion` | integer | Schema version. Currently `1`. Bumped on breaking shape changes. |
| `verifyResult.filesChecked` | integer | Number of `.nim` files parsed. |
| `verifyResult.transitionsChecked` | integer | Number of `{.transition.}` procs whose source/destination edges were validated. |
| `verifyResult.errors` | array | Findings with severity `error`. Empty array if none. |
| `verifyResult.warnings` | array | Findings with severity `warning`. Empty array if none. |
| `path` | string | Filesystem path to the source file, as provided to `verify`. |
| `line` | integer | 1-based line number. `0` if the finding is file-scoped (e.g., a parse error with no usable line info). |
| `column` | integer | 1-based column number. `0` if not available (most lints are line-scoped). Currently populated for `parse-error` findings via the Nim parser's caret position; other codes emit `0`. |
| `code` | string | Stable identifier for the check. See [Code taxonomy](#code-taxonomy). |
| `message` | string | Human-readable primary message. Single line. |
| `hint` | string | Secondary diagnostic text (suggestions, supplementary context). Empty string if absent. |

### Severity is array membership

There is no per-finding `severity` field. A finding's severity is encoded
by which array it appears in: entries in `errors[]` are errors, entries
in `warnings[]` are warnings. Flat consumers that want a single sequence
should concatenate the two arrays and tag each entry with its source
array's severity:

```python
import json
result = json.load(open('verify.json'))
findings = (
    [{'severity': 'error', **f} for f in result['verifyResult']['errors']]
    + [{'severity': 'warning', **f} for f in result['verifyResult']['warnings']]
)
```

This shape is deliberate: it keeps the wire format compact, mirrors the
internal `VerifyResult` structure, and matches the JSON shape produced
by `clang-tidy` and similar tools.

### Empty findings

When verification produces no findings, both arrays are present and
empty:

```json
{
  "schemaVersion": 1,
  "verifyResult": {
    "filesChecked": 42,
    "transitionsChecked": 17,
    "errors": [],
    "warnings": []
  }
}
```

Consumers should treat the absence of `errors` or `warnings` keys as a
schema violation, not as an empty result.

### Field-order guarantee

Field order in the JSON output is stable: top-level keys appear in the
order shown above (`schemaVersion`, then `verifyResult`), and finding
keys appear in `path, line, column, code, message, hint` order. This is achieved
via Nim's `std/json` `OrderedTable`-backed `JsonNode`. Consumers that
parse with insertion-order-preserving libraries (Python's `json`,
`jq -S` opt-out, etc.) get deterministic output. Consumers using
hash-randomized parsers should not rely on field order, but the schema
itself does not require ordering.

## Code taxonomy

Every finding carries a stable `code` identifier. The current set:

| Code | Severity | Meaning |
|---|---|---|
| `file-not-found` | error | A path passed to `verify` does not exist or is not readable. |
| `parse-error` | error | The Nim parser failed on a `.nim` file in the verified tree. |
| `unmarked-proc-strict` | error | Under `strictTransitions = true`, a proc on a typestate value is missing both `{.transition.}` and `{.notATransition.}`. |
| `unmarked-proc` | warning | Default-mode equivalent of `unmarked-proc-strict` (advisory). |
| `unreachable-state` | warning | A state has no incoming transitions and is not declared `initial:`. |
| `non-terminal-state` | warning | A state has no outgoing transitions and is not declared `terminal:`. |
| `orphan-state` | warning | A state has no incoming and no outgoing transitions. |
| `no-entry-point` | warning | The typestate has no `initial:` declaration and no inferable entry state. |
| `opaque-state-bypass` | warning | A non-initial state is constructed via call-syntax cast outside any `{.transition.}` proc, while the typestate is declared `opaqueStates = true`. |
| `opaque-states-no-initials` | warning | A typestate has `opaqueStates = true` but no `initial:` block (and no inferable initials). The lint is skipped for that typestate. |

## Stability policy

Codes are stable within a major version. Specifically:

- New codes may be added in minor versions. Consumers should treat
  unknown codes as warnings of unspecified semantics, not as schema
  violations.
- Code renames or removals require a major version bump and an
  increment of `schemaVersion`.
- The `severity` (which array a finding lands in) for an existing code
  may be promoted from warning to error in a major version, or relaxed
  from error to warning in a minor version.
- Field shapes (the keys on a finding object) are stable within a
  major version.

When `schemaVersion` increments, consumers should treat older shapes
as a separate dialect rather than attempting to autodetect.

## Local testing

`--format=github` is primarily intended for the GitHub Actions runner.
Run locally to inspect annotation rendering, but the default format is
more readable for interactive use.

`--format=json` is useful for piping to `jq`:

```bash
typestates verify --format=json src/ | jq '.verifyResult.errors[] | .path + ":" + (.line | tostring) + " " + .code'
```

For a quick warning count:

```bash
typestates verify --format=json src/ | jq '.verifyResult.warnings | length'
```

The default format remains the most ergonomic for local development:
human-readable lines with severity prefixes, suitable for editor
quickfix lists.
