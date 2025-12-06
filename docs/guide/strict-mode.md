# Strict Mode

nim-typestates uses strict defaults to catch bugs early.

## Default Behavior

By default, typestates have:

- `strictTransitions = true` - All procs with state params must be marked
- `consumeOnTransition = true` - State types cannot be copied

## consumeOnTransition

When enabled (default), state types cannot be copied. This prevents bugs where you accidentally use a stale state after transitioning:

```nim
typestate File:
  states Closed, Open
  transitions:
    Closed -> Open
    Open -> Closed

let closed = Closed(File(handle: 0))
let opened = closed.open()  # closed is consumed

# This would be a bug - closed already transitioned!
# let opened2 = closed.open()  # Compile error: cannot copy
```

The `=copy` hook is generated with an error pragma, ensuring compile-time enforcement.

### Opting Out

```nim
typestate LegacyFile:
  consumeOnTransition = false  # Allow copying
  states Closed, Open
  ...
```

Use this when you genuinely need to copy state (e.g., for logging the "before" state).

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

## Module Boundaries

Typestates can only be defined once, in a single module. All states and transitions
must be declared together:

```nim
# library.nim
typestate Payment:
  states Created, Captured
  transitions:
    Created -> Captured

# user_code.nim
import library

proc check(p: Created): bool {.notATransition.} = ...  # OK - read-only
proc hack(p: Created): Captured {.transition.} = ...   # ERROR - can't add transitions from external module
```

This ensures the typestate's behavior is fully defined where it's declared,
preventing accidental or malicious modification from other modules.
