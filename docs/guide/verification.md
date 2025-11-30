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

## CLI Verification Tool

For full-project analysis, use the nimble task:

```bash
nimble verify
```

Or specify paths:

```bash
nim c -r src/nim_typestates/cli.nim src/ tests/
```

### CI Integration

```yaml
# GitHub Actions
- name: Verify typestates
  run: nimble verify

# CircleCI
- run:
    name: Verify typestates
    command: nimble verify
```

### Output

```
Checked 15 files, 42 transitions
WARNING: src/legacy.nim:45 - Unmarked proc on state 'Open'
ERROR: src/user.nim:23 - Unmarked proc on sealed state 'Payment'

1 error(s) found
```
