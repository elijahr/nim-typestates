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

See [CLI Reference](cli.md) for complete usage and [Visualization](visualization.md) for diagram generation.
