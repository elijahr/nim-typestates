# Verification

The typestates library provides multiple verification layers.

## Compile-Time Checking

The `{.transition.}` and `{.notATransition.}` pragmas validate at compile time:

- Transitions match declared state machine
- Sealed typestates block external transitions

## verifyTypestates() Macro

For comprehensive in-module verification:

```nim
import typestates

typestate File:
  states Closed, Open
  ...

proc open(...) {.transition.} = ...
proc close(...) {.transition.} = ...

verifyTypestates()  # Validates everything above
```

## CLI Tool

The `typestates` CLI provides project-wide verification and visualization:

```bash
typestates verify src/     # Check all procs are properly marked
typestates dot src/        # Generate GraphViz diagrams
```

For non-interactive use, `verify` accepts `--warnings-as-errors` (alias `-W`) to promote warning-severity findings to a non-zero exit code, and `--format=github` or `--format=json` for machine-readable output. The `github` format emits inline PR annotations on GitHub Actions; the `json` format follows a stable, versioned schema for downstream tooling.

See [CLI Reference](cli.md) for complete usage, [CI Integration](ci-integration.md) for the format schemas and CI recipes, and [Visualization](visualization.md) for diagram generation.
