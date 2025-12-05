# Error Handling

Typestates model errors as states, not exceptions. If an operation can fail,
the failure is a state the object transitions to.

## The Rule

All `{.transition.}` procs must have `{.raises: [].}` - either explicitly
declared or inferred. The library enforces this at compile time.

### Why?

Exceptions bypass the state machine. If a transition raises an exception,
the caller never receives the promised state. The object's logical state
becomes undefined.

Error states are explicit and trackable. The type system knows about them,
and callers must handle them.

### Example

```nim
# Wrong: exception bypasses state machine
proc open(f: Closed, path: string): Open {.transition.} =
  if not fileExists(path):
    raise newException(IOError, "not found")  # Compile error!
  ...

# Right: error is a state, use branch type
proc open(f: Closed, path: string): ClosedBranch {.transition.} =
  if not fileExists(path):
    return toClosedBranch(OpenFailed(f.File))
  toClosedBranch(Open(f.File))
```

## Defects vs Exceptions

Nim distinguishes between **Defects** (bugs) and **CatchableErrors**
(recoverable errors).

### Defects

Programming errors that should not be caught:

- `IndexDefect` - array/seq index out of bounds
- `DivByZeroDefect` - division by zero
- `AssertionDefect` - failed assertion

Defects are NOT tracked by the `{.raises.}` pragma. A proc can have
`{.raises: [].}` but still trigger a Defect if there's a bug.

### CatchableErrors

Recoverable errors that callers can handle:

- `IOError` - file/network operations
- `ValueError` - parsing, conversion
- `OSError` - system calls

These ARE tracked by `{.raises.}`. Our enforcement prevents transitions
from raising them.

### What Typestates Guarantee

The library guarantees *protocol correctness* - you cannot call operations
in the wrong state. It does NOT guarantee *implementation correctness* -
your transition body might still have bugs that trigger Defects.

Recommendation: Avoid Defect-prone operations in transitions, or guard them:

```nim
# Risky: seq[i] can raise IndexDefect
proc getItem(c: HasItems): Item {.transition, raises: [].} =
  result = c.items[0]  # Bug if items is empty!

# Safer: check first, return error state
proc getItem(c: HasItems): HasItemsBranch {.transition, raises: [].} =
  if c.items.len == 0:
    return toHasItemsBranch(Empty(c.Container))
  toHasItemsBranch(Item(c.items[0]))
```

## Patterns

### Branching Transitions

For transitions that can result in multiple states (success or failure),
nim-typestates generates branch types. Given:

```nim
typestate Connection:
  states Disconnected, Connected, ConnectionFailed
  transitions:
    Disconnected -> Connected | ConnectionFailed
    Connected -> Disconnected
    ConnectionFailed -> Disconnected
```

The macro generates:
- `DisconnectedBranchKind` - enum with `dbConnected`, `dbConnectionFailed`
- `DisconnectedBranch` - variant object holding the result
- `toDisconnectedBranch(s: Connected)` - constructor
- `toDisconnectedBranch(s: ConnectionFailed)` - constructor

Use them in your transition:

```nim
proc connect(c: Disconnected, host: string): DisconnectedBranch {.transition, raises: [].} =
  try:
    let socket = connectSocket(host)
    var conn = Connected(c.Connection)
    conn.Connection.socket = socket
    toDisconnectedBranch(conn)
  except OSError:
    toDisconnectedBranch(ConnectionFailed(c.Connection))
```

Then pattern match on the result:

```nim
let result = connect(disconnected, "localhost")
case result.kind
of dbConnected:
  echo "Connected!"
  use(result.connected)
of dbConnectionFailed:
  echo "Failed to connect"
  retry(result.connectionfailed)
```

### Wrap External Calls

Create `{.raises: [].}` wrappers for exception-throwing APIs:

```nim
proc tryReadFile(path: string): Option[string] {.raises: [].} =
  try:
    result = some(readFile(path))
  except IOError:
    result = none(string)

proc load(f: Empty, path: string): EmptyBranch {.transition, raises: [].} =
  let content = tryReadFile(path)
  if content.isNone:
    return toEmptyBranch(LoadFailed(f.Document))
  var loaded = Loaded(f.Document)
  loaded.Document.content = content.get
  toEmptyBranch(loaded)
```

### Result Types

Use Result[T, E] for structured error handling:

```nim
proc load(f: Empty, path: string): EmptyBranch {.transition, raises: [].} =
  let content = readFileResult(path)  # returns Result[string, IOError]
  if content.isErr:
    return toEmptyBranch(LoadFailed(f.Document))
  var loaded = Loaded(f.Document)
  loaded.Document.content = content.get
  toEmptyBranch(loaded)
```
