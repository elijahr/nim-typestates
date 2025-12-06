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

The `verify` command checks that all procs operating on state types are properly marked with `{.transition.}` or `{.notATransition.}`.

### Basic Usage

```bash
typestates verify src/
typestates verify src/ tests/
typestates verify .
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

### Syntax Error Handling

The CLI uses Nim's AST parser for accurate extraction. Files must be valid Nim syntax:

```bash
$ typestates verify src/
ERROR: Parse error in src/broken.nim: invalid indentation
```

This is intentional - a verification tool should not silently skip files it cannot parse.

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

### GitHub Actions

```yaml
- name: Install typestates
  run: nimble install typestates -y

- name: Verify typestates
  run: typestates verify src/
```

### CircleCI

```yaml
- run:
    name: Verify typestates
    command: |
      nimble install typestates -y
      typestates verify src/
```

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
