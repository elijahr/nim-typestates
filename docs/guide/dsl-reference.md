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

One source state to multiple possible destinations using `|`:

```nim
Closed -> Open | Errored
```

This means a proc taking `Closed` can return either `Open` or `Errored`.

### Wildcard Transitions

Any state can transition to a destination using `*`:

```nim
* -> Closed
```

Wildcards are useful for "reset" or "cleanup" operations that work from any state.

## Bridges

Cross-typestate transitions declared with dotted notation.

### Syntax

```nim
bridges:
  SourceState -> DestTypestate.DestState
  SourceState -> DestTypestate.State1 | DestTypestate.State2  # Branching
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
  Authenticated -> Session.Active | Session.Guest
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
- Must have `{.raises: [].}` - errors should be states, not exceptions

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
    Connecting -> Connected | Errored
    Connected -> Disconnected
    Errored -> Disconnected
    * -> Disconnected  # Can always disconnect

proc connect(c: Disconnected, host: string, port: int): Connecting {.transition.} =
  var conn = c.Connection
  conn.host = host
  conn.port = port
  result = Connecting(conn)

proc waitForConnection(c: Connecting): Connected | Errored {.transition.} =
  # In real code, this would do async I/O
  if true:  # Pretend success
    result = Connected(c.Connection)
  else:
    result = Errored(c.Connection)

proc disconnect[S: ConnectionStates](c: S): Disconnected {.transition.} =
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

For branching transitions, return a union:

```nim
proc tryOpen(f: Closed): Open | Errored {.transition.} =
  if success:
    result = Open(f.File)
  else:
    result = Errored(f.File)
```

### Generic Over All States

Use the generated union type for generic procs:

```nim
proc forceClose[S: FileStates](f: S): Closed =
  Closed(f.File)
```
