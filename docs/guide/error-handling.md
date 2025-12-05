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
# (assumes: Closed -> Open | OpenFailed as OpenResult)
proc open(f: Closed, path: string): OpenResult {.transition.} =
  if not fileExists(path):
    return OpenResult -> OpenFailed(f.File)
  OpenResult -> Open(f.File)
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
# (assumes: HasItems -> Item | Empty as GetItemResult)
proc getItem(c: HasItems): GetItemResult {.transition, raises: [].} =
  if c.items.len == 0:
    return GetItemResult -> Empty(c.Container)
  GetItemResult -> Item(c.items[0])
```

## Patterns

### Branching Transitions

For transitions that can result in multiple states (success or failure),
use the `as TypeName` syntax to name the branch type. Given:

```nim
typestate Connection:
  states Disconnected, Connected, ConnectionFailed
  transitions:
    Disconnected -> Connected | ConnectionFailed as ConnectResult
    Connected -> Disconnected
    ConnectionFailed -> Disconnected
```

The macro generates branch types and the `->` operator for constructing results.

Use the `->` operator in your transition:

```nim
proc connect(c: Disconnected, host: string): ConnectResult {.transition, raises: [].} =
  try:
    let socket = connectSocket(host)
    var conn = Connected(c.Connection)
    conn.Connection.socket = socket
    ConnectResult -> conn
  except OSError:
    ConnectResult -> ConnectionFailed(c.Connection)
```

The `->` operator takes the branch type on the left and the destination state on the right.

Then pattern match on the result:

```nim
let result = connect(disconnected, "localhost")
case result.kind
of cConnected:
  echo "Connected!"
  use(result.connected)
of cConnectionFailed:
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

# (assumes: Empty -> Loaded | LoadFailed as LoadResult)
proc load(f: Empty, path: string): LoadResult {.transition, raises: [].} =
  let content = tryReadFile(path)
  if content.isNone:
    return LoadResult -> LoadFailed(f.Document)
  var loaded = Loaded(f.Document)
  loaded.Document.content = content.get
  LoadResult -> loaded
```

### Result Types

Use Result[T, E] for structured error handling:

```nim
# (assumes: Empty -> Loaded | LoadFailed as LoadResult)
proc load(f: Empty, path: string): LoadResult {.transition, raises: [].} =
  let content = readFileResult(path)  # returns Result[string, IOError]
  if content.isErr:
    return LoadResult -> LoadFailed(f.Document)
  var loaded = Loaded(f.Document)
  loaded.Document.content = content.get
  LoadResult -> loaded
```
