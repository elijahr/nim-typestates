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
# (assumes: Closed -> (Open | OpenFailed) as OpenResult)
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
# (assumes: HasItems -> (Item | Empty) as GetItemResult)
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
    Disconnected -> (Connected | ConnectionFailed) as ConnectResult
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

Or use the auto-generated `match` macro for compile-time exhaustiveness:

```nim
var result = connect(disconnected, "localhost")
match result:
  Connected(c):
    echo "Connected!"
    use(c)
  ConnectionFailed(f):
    echo "Failed to connect"
    retry(f)
```

The matched value must be a `var` binding (branch fields are extracted with
`move()`), the syntax is `StateName(bind):` (not `of StateName as bind:`),
and every branch must be covered — there is no `else:` escape hatch. See
[Pattern matching with `match`](dsl-reference.md#branch-types) in the DSL
reference for details.

### Wrap External Calls

Create `{.raises: [].}` wrappers for exception-throwing APIs:

```nim
proc tryReadFile(path: string): Option[string] {.raises: [].} =
  try:
    result = some(readFile(path))
  except IOError:
    result = none(string)

# (assumes: Empty -> (Loaded | LoadFailed) as LoadResult)
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
# (assumes: Empty -> (Loaded | LoadFailed) as LoadResult)
proc load(f: Empty, path: string): LoadResult {.transition, raises: [].} =
  let content = readFileResult(path)  # returns Result[string, IOError]
  if content.isErr:
    return LoadResult -> LoadFailed(f.Document)
  var loaded = Loaded(f.Document)
  loaded.Document.content = content.get
  LoadResult -> loaded
```

### Result as a Direct Return Type

Transitions can return `Result[State, E]` directly — the library
unwraps common wrappers (`Result`, `Option`, `Future`) and validates
the underlying state:

```nim
import results

# (assumes: Proposed -> PreChecked)
proc preCheck(p: Proposed): Result[PreChecked, GateRejection] {.transition.} =
  if rejected:
    err(GateRejection.InvalidAmount)
  else:
    ok(PreChecked(Order(p)))
```

Use this pattern when there is exactly one success state and the
error channel carries data. Use branch types (`... as LoadResult`) 
when the "failure" is itself a distinct state in the machine.

For async procs, return `Future[T]` or `Future[Result[T, E]]` with
`{.async, transition.}` — the chain unwraps through both wrappers.
See [Transparent Wrappers](transparent-wrappers.md).

## State-Aware Error Messages

Calling a transition on the wrong source state used to surface Nim's
generic `Error: type mismatch` diagnostic. Starting in v0.5, every module
that ends with `verifyTypestates()` automatically emits `{.error.}` decoy
overloads alongside each non-generic, non-branching `{.transition.}` proc.
The decoys cover the *other* states of the same typestate, so misuse fires
a tailored message naming the proc, the wrong state, and the expected
source state.

```nim
typestate Door:
  states Closed, Open, Locked
  transitions:
    Closed -> Open
    Open -> Locked

proc unlock(d: sink Closed): Open {.transition.} =
  Open(Door(d))

proc lock(d: sink Open): Locked {.transition.} =
  Locked(Door(d))

verifyTypestates()  # required for state-aware errors

let c = Closed(Door())
discard c.lock()
# Error: Cannot call 'lock' on a value in state 'Closed'.
#   Expected 'Open'. (Defined at <module>)
```

The trailing parameters of the original transition are preserved on the
decoy, so `proc close(a: sink Active, reason: string)` produces decoys
shaped `proc close(p: sink Frozen, reason: string)`, ensuring overload
resolution selects the decoy at the call site even when the user passed
extra arguments.

### When decoys are *not* emitted

The v0.5 pass intentionally skips three categories. Misuse in these
configurations still fails to compile, but with the standard `type
mismatch` message rather than the tailored one. Lifting these
restrictions is tracked as a v0.6 follow-up.

- **Generic typestates** (`typestate Container[T]:`). The decoy codegen
  needs to thread the typestate's generic parameters through each
  decoy `nnkProcDef`, which v0.5 does not do.
- **Branching-return transitions** (`Created -> (Approved | Declined)
  as ProcessResult`). A decoy returning `auto` cannot represent the
  branch shape unambiguously.
- **Union-source transitions** (`proc f(s: Open | PartiallyFilled): ...`).
  A union source already covers multiple states; deriving the
  *uncovered* states from a union is deferred.

If `verifyTypestates()` is omitted from a module, no decoys are emitted
and you fall back to Nim's default error. Keep the call as the last
statement of the module so all transitions and overloads have been
registered before the decoy pass runs.
