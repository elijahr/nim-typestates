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

# Right: error is a state
proc open(f: Closed, path: string): Open | OpenFailed {.transition.} =
  if not fileExists(path):
    return OpenFailed(f.File)
  ...
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
proc getItem(c: HasItems): Item | Empty {.transition, raises: [].} =
  if c.items.len == 0:
    return Empty(c.Container)
  result = Item(c.items[0])
```

## Patterns

### Union Return Types

Declare all possible outcomes in the return type:

```nim
typestate Connection:
  states Disconnected, Connected, ConnectionFailed
  transitions:
    Disconnected -> Connected | ConnectionFailed
    Connected -> Disconnected
    ConnectionFailed -> Disconnected

proc connect(c: Disconnected, host: string): Connected | ConnectionFailed {.transition, raises: [].} =
  try:
    let socket = connectSocket(host)
    result = Connected(c.Connection)
    result.Connection.socket = socket
  except OSError:
    result = ConnectionFailed(c.Connection)
```

### Wrap External Calls

Create `{.raises: [].}` wrappers for exception-throwing APIs:

```nim
proc tryReadFile(path: string): Option[string] {.raises: [].} =
  try:
    result = some(readFile(path))
  except IOError:
    result = none(string)

proc load(f: Empty, path: string): Loaded | LoadFailed {.transition, raises: [].} =
  let content = tryReadFile(path)
  if content.isNone:
    return LoadFailed(f.Document)
  result = Loaded(f.Document)
  result.Document.content = content.get
```

### Result Types

Use Result[T, E] for structured error handling:

```nim
proc load(f: Empty, path: string): Loaded | LoadFailed {.transition, raises: [].} =
  let content = readFileResult(path)  # returns Result[string, IOError]
  if content.isErr:
    return LoadFailed(f.Document)
  result = Loaded(f.Document)
  result.Document.content = content.get
```
