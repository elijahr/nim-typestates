# Command Line Interface

The `typestates` command-line tool provides project-wide verification and visualization capabilities.

## Installation

The CLI is installed automatically with the library:

```bash
nimble install typestates
```

## Usage

```
typestates <command> [paths...]

Commands:
  verify    Check that procs on state types are properly marked
  dot       Generate GraphViz DOT output for visualization

Options:
  -h, --help      Show help
  -v, --version   Show version
```

## Verify Command

The `verify` command checks that all procs operating on state types are properly marked with `{.transition.}` or `{.notATransition.}`. It also surfaces reachability problems, opaque-state cast bypasses, and configuration warnings.

### Basic Usage

```bash
typestates verify src/
typestates verify src/ tests/
typestates verify .
```

### Flags

The `verify` command accepts two flags that shape exit-code policy and output format. See [CI Integration](ci-integration.md) for the full schema, severity model, and CI-specific recipes.

#### `--warnings-as-errors` (alias `-W`)

Promotes any warning-severity finding to a non-zero exit code. Findings keep their `warning` label in human and JSON output; only the exit-code policy changes (matching the convention of `gcc -Werror`).

```bash
typestates verify --warnings-as-errors src/
typestates verify -W src/
```

#### `--format=<default|github|json>`

Selects the output format. `default` is the human-readable rendering used for interactive runs. `github` emits one annotation line per finding in GitHub Actions' `::error`/`::warning` workflow-command syntax, suitable for inline PR-diff annotations. `json` emits a stable, versioned schema (`schemaVersion: 1`) suitable for downstream tooling.

```bash
typestates verify --format=github src/
typestates verify --format=json src/ | jq '.verifyResult.errors'
```

### Example

Given this file `src/file_state.nim`:

```nim
import typestates

type
  File = object
    path: string
  Closed = distinct File
  Open = distinct File

typestate File:
  states Closed, Open
  transitions:
    Closed -> Open
    Open -> Closed

proc open(f: Closed): Open {.transition.} =
  result = Open(f)

proc close(f: Open): Closed {.transition.} =
  result = Closed(f)
```

Running verification:

```bash
$ typestates verify src/
Checked 1 files, 2 transitions

All checks passed!
```

### Error Output

If a proc is missing the required pragma:

```nim
# Missing {.transition.} pragma!
proc open(f: Closed): Open =
  result = Open(f)
```

```bash
$ typestates verify src/
Checked 1 files, 1 transitions
ERROR: src/file_state.nim:15 - Unmarked proc on state 'Closed' (strictTransitions enabled)

1 error(s) found
```

Each line above corresponds to a structured `Finding` record (path, line, column, code, message, hint). The default format renders these for human consumption; pass `--format=github` for inline PR annotations or `--format=json` for the documented schema. See [CI Integration](ci-integration.md) for the full code taxonomy and field semantics.

### Syntax Error Handling

The CLI uses Nim's AST parser for accurate extraction. Files must be valid Nim syntax:

```bash
$ typestates verify src/
ERROR: src/broken.nim:2 - invalid indentation
```

A parse failure is reported as a structured `parse-error` finding for that path (rendered through the same `path:line - message` formatter as other findings) and does not abort the run. Each input file is parsed independently, so a single malformed file (for example, an unfinished change pushed by a contributor) produces one finding while verification continues across the rest of the batch. Earlier versions of `typestates verify` aborted on the first parse failure.

## Dot Command

The `dot` command generates GraphViz DOT output for visualizing state machines.

See [Visualization](visualization.md) for detailed usage and examples.

### Basic Usage

```bash
typestates dot src/
typestates dot src/ > states.dot
typestates dot src/ | dot -Tpng -o states.png
```

### Options

| Option | Description |
|--------|-------------|
| `--splines=MODE` | Edge routing: `spline` (default), `ortho`, `polyline`, `line` |
| `--separate` | Generate separate graph per typestate |
| `--no-style` | Output minimal DOT without styling |

```bash
# Curved edges (default)
typestates dot src/

# Right-angle edges
typestates dot --splines=ortho src/

# Minimal output for custom styling
typestates dot --no-style src/
```

## CI Integration

See [CI Integration](ci-integration.md) for the full guide: pre-commit hook, GitHub Actions and GitLab CI recipes, the `--format=github` annotation workflow, the `--format=json` schema, severity model, and the stable code taxonomy.

## Nimble Task

Add a verification task to your `.nimble` file:

```nim
task verify, "Verify typestate rules":
  exec "typestates verify src/"
```

Then run:

```bash
nimble verify
```
