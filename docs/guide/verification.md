# Verification

nim-typestates provides multiple verification layers.

## Compile-Time Checking

The `{.transition.}` and `{.notATransition.}` pragmas validate at compile time:
- Transitions match declared state machine
- Sealed typestates block external transitions

## verifyTypestates() Macro

For comprehensive in-module verification:

```nim
import nim_typestates

typestate File:
  states Closed, Open
  ...

proc open(...) {.transition.} = ...
proc close(...) {.transition.} = ...

verifyTypestates()  # Validates everything above
```

## CLI Tool

The library installs a `nim-typestates` binary for project-wide verification and visualization.

The CLI uses Nim's AST parser for accurate extraction of typestate definitions, correctly handling comments, whitespace, and complex syntax.

**Important:** Files must be valid Nim syntax. Syntax errors cause verification to fail immediately with a clear error message. This is intentional - a verification tool should not silently skip files it cannot parse.

### Verify

Check that all procs on state types are properly marked:

```bash
nim-typestates verify src/
nim-typestates verify src/ tests/
```

### Generate GraphViz DOT

Export state machine diagrams:

```bash
nim-typestates dot src/ > typestates.dot
nim-typestates dot src/ | dot -Tpng -o typestates.png
```

### Adding a Nimble Task

Add this to your project's `.nimble` file:

```nim
task verify, "Verify typestate rules":
  exec "nim-typestates verify src/"
```

Then run:

```bash
nimble verify
```

### CI Integration

```yaml
# GitHub Actions
- name: Verify typestates
  run: nim-typestates verify src/

# CircleCI
- run:
    name: Verify typestates
    command: nim-typestates verify src/
```

### Output

Successful verification:

```
Checked 15 files, 42 transitions

All checks passed!
```

Errors found:

```
Checked 15 files, 42 transitions
WARNING: src/legacy.nim:45 - Unmarked proc on state 'Open'
ERROR: src/user.nim:23 - Unmarked proc on sealed state 'Payment'

1 error(s) found
```

Syntax errors:

```
ERROR: Parse error in src/broken.nim: invalid indentation
```
