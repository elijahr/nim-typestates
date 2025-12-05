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
