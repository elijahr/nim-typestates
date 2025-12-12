# Cross-Type State Bridges

Bridges allow terminal states of one typestate to transition into states of a completely different typestate. This enables modeling resource transformation, wrapping, and protocol handoff.

## Declaration

Declare bridges in the source typestate using a `bridges:` block with dotted notation:

```nim
import session

typestate AuthFlow:
  states Pending, Authenticated, Failed
  transitions:
    Pending -> Authenticated
    Pending -> Failed
  bridges:
    Authenticated -> Session.Active
    Failed -> ErrorLog.Entry
```

The destination typestate must be imported and exist.

### Module-Qualified Syntax

For clarity when bridging to typestates from other modules, use the full module-qualified syntax:

```nim
import ./session_module

typestate AuthFlow:
  states Pending, Authenticated
  transitions:
    Pending -> Authenticated
  bridges:
    # Explicit module prefix for clarity
    Authenticated -> session_module.Session.Active
```

This syntax is especially useful when:

- Multiple modules define typestates with similar names
- You want to make cross-module dependencies explicit
- Working with library typestates (see [Library Modularity](library-modularity.md))

## Implementation

### Using Procs

Use procs when you need extra arguments:

```nim
proc startSession(auth: Authenticated, config: SessionConfig): Active {.transition.} =
  result = Active(Session(
    userId: auth.AuthFlow.userId,
    timeout: config.timeout
  ))
```

### Using Converters

Use converters for simple 1:1 transforms:

```nim
converter toSession(auth: Authenticated): Active {.transition.} =
  Active(Session(userId: auth.AuthFlow.userId))

# Usage - implicit conversion works
let session: Active = myAuth
```

## Branching

Bridges support branching like regular transitions:

```nim
bridges:
  Authenticated -> Session.Active | Session.Guest
```

## Wildcard Bridges

Use `*` to allow any state to bridge to a destination:

```nim
bridges:
  * -> Shutdown.Terminal
```

## Validation

The compiler validates:

1. Bridge is declared in source typestate's `bridges:` block
2. Proc/converter signature matches declaration
3. Destination typestate exists
4. Destination state exists in that typestate
5. Destination module is imported

## Error Messages

### Bridge Not Declared

```
Error: Undeclared bridge: Authenticated -> Session.Active
  Typestate 'AuthFlow' does not declare this bridge.
  Valid bridges from 'Authenticated': @[]
  Hint: Add 'bridges: Authenticated -> Session.Active' to AuthFlow.
```

### Unknown Typestate

If you reference a typestate that doesn't exist, you'll get an error indicating that the destination type isn't part of any registered typestate.

### Unknown State

If you reference a state that doesn't exist in the destination typestate, you'll get an error indicating which states are valid.

## Complete Example

```nim
# session.nim
import typestates

type
  Session = object
    userId: string
  Active = distinct Session
  Expired = distinct Session

typestate Session:
  states Active, Expired
  transitions:
    Active -> Expired

# auth.nim
import typestates
import ./session

type
  AuthFlow = object
    userId: string
  Pending = distinct AuthFlow
  Authenticated = distinct AuthFlow

typestate AuthFlow:
  states Pending, Authenticated
  transitions:
    Pending -> Authenticated
  bridges:
    Authenticated -> Session.Active

converter toSession(a: Authenticated): Active {.transition.} =
  Active(Session(userId: a.AuthFlow.userId))
```

## Cross-Module Considerations

### consumeOnTransition and Bridges

**Important:** When bridging between typestates from different modules, both typestates should use `consumeOnTransition = false`.

With `consumeOnTransition = true` (the default), state values cannot be copied. When a bridge proc takes a state from typestate A and creates a state in typestate B, the value must be passed across module boundaries. This can trigger copy errors if either typestate has copy disabled.

```nim
# module_a.nim
typestate AuthFlow:
  consumeOnTransition = false  # Required for cross-module bridging
  states Pending, Authenticated
  bridges:
    Authenticated -> Session.Active

# module_b.nim
typestate Session:
  consumeOnTransition = false  # Required for cross-module bridging
  states Active, Expired
```

If you see errors like `'=copy' is not available for type <State>` when using bridges, add `consumeOnTransition = false` to both the source and destination typestates.

## Visualization

### Unified Graph (default)

```bash
typestates dot src/
```

Shows all typestates with cross-cluster dashed edges for bridges.

### Separate Graphs

```bash
typestates dot --separate src/
```

Shows individual graphs per typestate with bridges as terminal nodes.
