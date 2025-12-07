# DSL Reference

Complete reference for the nim-typestates DSL syntax.

## Typestate Block

```nim
typestate TypeName:
  states State1, State2, State3
  transitions:
    State1 -> State2
    State2 -> State3
```

### States Declaration

List all state types that participate in this typestate:

```nim
states Closed, Open, Reading, Writing, Errored
```

Or use multiline format for readability:

```nim
states:
  Closed
  Open
  Reading
  Writing
  Errored
```

Each state must be a `distinct` type of the base type:

```nim
type
  File = object
    # ...
  Closed = distinct File
  Open = distinct File
```

### Transitions Block

Declare valid state transitions using `->` syntax:

```nim
transitions:
  Closed -> Open
  Open -> Closed
```

## Transition Syntax

### Simple Transitions

One source state to one destination:

```nim
Closed -> Open
```

### Branching Transitions

One source state to multiple possible destinations using `|`, with a required result type name:

```nim
Closed -> (Open | Errored) as OpenResult
```

The `as TypeName` syntax names the generated branch type. This is required for all branching transitions.

This means a proc taking `Closed` can return either `Open` or `Errored`, wrapped in an `OpenResult` variant type.

### Wildcard Transitions

Any state can transition to a destination using `*`:

```nim
* -> Closed
```

Wildcards are useful for "reset" or "cleanup" operations that work from any state.

## Initial and Terminal States

Declare entry and exit points for your typestate:

### Initial States

States that can only be constructed, not transitioned TO:

```nim
initial: Disconnected
```

Or multiple:

```nim
initial: Disconnected, Starting
```

Attempting to transition TO an initial state produces a compile-time error:

```
Error: Cannot transition TO initial state 'Disconnected'.
  Initial states can only be constructed, not transitioned to.
```

### Terminal States

States that cannot transition FROM (end states):

```nim
terminal: Closed
```

Or multiple:

```nim
terminal: Closed, Failed
```

Attempting to transition FROM a terminal state produces a compile-time error:

```
Error: Cannot transition FROM terminal state 'Closed'.
  Terminal states are end states with no outgoing transitions.
```

### Complete Example

```nim
typestate Connection:
  states Disconnected, Connected, Closed
  initial: Disconnected
  terminal: Closed
  transitions:
    Disconnected -> Connected
    Connected -> Closed
```

## Bridges

Cross-typestate transitions declared with dotted notation.

### Syntax

```nim
bridges:
  SourceState -> DestTypestate.DestState
  SourceState -> (DestTypestate.State1 | DestTypestate.State2)  # Branching
  * -> DestTypestate.DestState  # Wildcard
```

### Requirements

- Destination typestate must be imported
- Destination typestate and state must exist
- Bridge must be declared before implementation

### Examples

Simple bridge:

```nim
bridges:
  Authenticated -> Session.Active
```

Branching bridge:

```nim
bridges:
  Authenticated -> (Session.Active | Session.Guest)
```

Wildcard bridge:

```nim
bridges:
  * -> Shutdown.Terminal
```

See [Bridges](bridges.md) for full documentation.

## Pragmas

### `{.transition.}`

Mark a proc as a state transition. The compiler validates that the transition is declared.

```nim
proc open(f: Closed): Open {.transition.} =
  result = Open(f)
```

**Validation rules:**

- First parameter must be a registered state type
- Return type must be a valid transition target
- Transition must be declared in the typestate block
- Automatically gets `{.raises: [].}` added if not specified - errors should be states, not exceptions
- If you explicitly write `{.raises: [SomeError].}`, compilation will fail

See [Error Handling](error-handling.md) for patterns on modeling errors as states.

**Error on invalid transition:**

```
Error: Undeclared transition: Open -> Locked
  Typestate 'File' does not declare this transition.
  Valid transitions from 'Open': @["Closed"]
  Hint: Add 'Open -> Locked' to the transitions block.
```

### `{.notATransition.}`

Mark a proc as intentionally NOT a transition. Use for procs that operate on state types but don't change state:

```nim
proc write(f: Open, data: string) {.notATransition.} =
  # Writes data but stays in Open state
  rawWrite(f.File.handle, data)

proc read(f: Open, count: int): string {.notATransition.} =
  # Reads data but stays in Open state
  result = rawRead(f.File.handle, count)
```

For pure functions (no side effects), use `func` instead - no pragma needed:

```nim
func path(f: Open): string =
  f.File.path
```

## Generated Types

For `typestate File:` with states `Closed`, `Open`, `Errored`:

### State Enum

```nim
type FileState* = enum
  fsClosed, fsOpen, fsErrored
```

Enum values are prefixed with `fs` (for "file state") to avoid name collisions.

### Union Type

```nim
type FileStates* = Closed | Open | Errored
```

Useful for generic procs that accept any state:

```nim
proc describe[S: FileStates](f: S): string =
  case f.state
  of fsClosed: "closed"
  of fsOpen: "open"
  of fsErrored: "errored"
```

### State Procs

```nim
proc state*(f: Closed): FileState = fsClosed
proc state*(f: Open): FileState = fsOpen
proc state*(f: Errored): FileState = fsErrored
```

### Branch Types

For branching transitions like `Created -> (Approved | Declined | Review) as ProcessResult`, the macro generates types and helpers for returning multiple possible states.

**Usage with the `->` operator:**

```nim
proc process(c: Created): ProcessResult {.transition.} =
  if c.Payment.amount > 100:
    ProcessResult -> Approved(c.Payment)
  elif c.Payment.amount > 50:
    ProcessResult -> Review(c.Payment)
  else:
    ProcessResult -> Declined(c.Payment)
```

The `->` operator takes the branch type on the left and the destination state on the right. This mirrors the DSL syntax and is unambiguous even when the same state appears in multiple branch types.

**Pattern matching on the result:**

```nim
let result = process(created)
case result.kind
of pApproved: echo "Approved: ", result.approved.Payment.amount
of pDeclined: echo "Declined"
of pReview: echo "Needs review"
```

**What gets generated:**

The `->` operator is syntactic sugar around constructor procs. For each branching transition with `as TypeName`, the macro generates:

1. **Enum** - `ProcessResultKind = enum pApproved, pDeclined, pReview`
   (prefix is first letter of type name, e.g., `p` for **P**rocessResult)

2. **Variant object** - `ProcessResult` holding the result

3. **Constructor procs** - `toProcessResult(s: Approved): ProcessResult` etc.

4. **`->` operator** - `template ->(T: typedesc[ProcessResult], s: Approved)` etc.

You can use the constructors directly if preferred:

```nim
toProcessResult(Approved(c.Payment))  # Equivalent to: ProcessResult -> Approved(c.Payment)
```

See [Returning Union Types](#returning-union-types) for more examples.

## Complete Example

```nim
import typestates

type
  Connection = object
    host: string
    port: int
    socket: int

  Disconnected = distinct Connection
  Connecting = distinct Connection
  Connected = distinct Connection
  Errored = distinct Connection

typestate Connection:
  states Disconnected, Connecting, Connected, Errored
  transitions:
    Disconnected -> Connecting
    Connecting -> (Connected | Errored) as ConnectResult
    Connected -> Disconnected
    Errored -> Disconnected
    * -> Disconnected  # Can always disconnect

proc connect(c: Disconnected, host: string, port: int): Connecting {.transition.} =
  var conn = c.Connection
  conn.host = host
  conn.port = port
  result = Connecting(conn)

proc waitForConnection(c: Connecting): ConnectResult {.transition.} =
  # In real code, this would do async I/O
  if true:  # Pretend success
    ConnectResult -> Connected(c.Connection)
  else:
    ConnectResult -> Errored(c.Connection)

# Wildcard transitions require separate procs for each source state.
# The {.transition.} pragma validates each at compile time.
proc disconnect(c: Disconnected): Disconnected {.transition.} =
  result = c  # Already disconnected

proc disconnect(c: Connecting): Disconnected {.transition.} =
  var conn = c.Connection
  conn.socket = 0
  result = Disconnected(conn)

proc disconnect(c: Connected): Disconnected {.transition.} =
  var conn = c.Connection
  conn.socket = 0
  result = Disconnected(conn)

proc disconnect(c: Errored): Disconnected {.transition.} =
  var conn = c.Connection
  conn.socket = 0
  result = Disconnected(conn)

proc send(c: Connected, data: string) {.notATransition.} =
  # Send data, stay connected
  discard
```

## Tips

### Accessing the Base Type

State types are `distinct`, so you need to convert to access fields:

```nim
proc path(f: Open): string =
  f.File.path  # Convert Open to File to access .path
```

### Returning Union Types

For branching transitions, use the `->` operator with the generated branch type:

```nim
# Branching transition: Connecting -> (Connected | Errored) as ConnectResult
proc waitForConnection(c: Connecting): ConnectResult {.transition.} =
  if success:
    ConnectResult -> Connected(c.Connection)
  else:
    ConnectResult -> Errored(c.Connection)
```

Then pattern match on the result:

```nim
let result = conn.waitForConnection()
case result.kind
of cConnected:
  echo "Connected!"
  sendData(result.connected)
of cErrored:
  echo "Error: ", result.errored.message
```

**Why branch types?** Nim's `A | B` syntax creates a generic type constraint, not a runtime sum type. You cannot actually return different types from if/else branches. The generated branch types solve this by wrapping the result in an object variant.

### Generic Over All States

Use the generated union type for generic procs:

```nim
proc forceClose[S: FileStates](f: S): Closed =
  Closed(f.File)
```
