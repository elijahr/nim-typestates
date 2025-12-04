# Strict Mode

nim-typestates uses strict defaults to catch bugs early.

## Default Behavior

By default, typestates have:

- `strictTransitions = true` - All procs with state params must be marked
- `isSealed = true` - External modules cannot add transitions

## strictTransitions

When enabled, any proc with a state type as its first parameter MUST have either:

- `{.transition.}` - for state-changing operations
- `{.notATransition.}` - for read-only operations

```nim
typestate File:
  states Closed, Open
  transitions:
    Closed -> Open

proc open(f: Closed): Open {.transition.} = ...     # OK
proc read(f: Open): string {.notATransition.} = ... # OK
proc helper(f: Open): int = ...                     # ERROR!
```

### Opting Out

```nim
typestate LegacyFile:
  strictTransitions = false
  states Closed, Open
  ...
```

## isSealed

When enabled:

1. Other modules cannot extend the typestate
2. Other modules cannot define `{.transition.}` procs
3. Other modules MUST use `{.notATransition.}` for any state operations

```nim
# library.nim
typestate Payment:
  # isSealed = true (default)
  states Created, Captured

# user_code.nim
import library

proc check(p: Created): bool {.notATransition.} = ...  # OK
proc hack(p: Created): Captured {.transition.} = ...   # ERROR!
```

### Opting Out

```nim
typestate ExtensiblePayment:
  isSealed = false
  ...
```
