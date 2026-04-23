# Transparent Wrappers

Starting in v0.4.0, `{.transition.}` looks through common wrapper types
(`Result`, `Option`, `Future`) to find the destination state. A proc
that returns `Result[B, E]`, `Option[B]`, or `Future[B]` from source
`A` validates the `A -> B` edge — the wrapper is transparent to the
transition check.

You can also register your own wrappers.

## Built-in Wrappers

The following generic types are registered out of the box:

| Type | Module | Typical use |
|------|--------|-------------|
| `Result[T, E]` | [arnetheduck/nim-results](https://github.com/arnetheduck/nim-results) | Structured success/error return |
| `Option[T]` | `std/options` | Optional value |
| `Future[T]` | `chronos` / `std/asyncdispatch` | Async result |

Wrappers chain: `Future[Result[T, E]]` unwraps through both layers, so
the common async-with-error return shape validates the final state.

## Return-Type Validation

### `Result[T, E]`

```nim
import results

proc preCheck(p: Proposed): Result[PreChecked, string] {.transition.} =
  ok(PreChecked(Order(p)))
```

The pragma unwraps `Result[PreChecked, string]` to `PreChecked` and
verifies the `Proposed -> PreChecked` edge.

### `Option[T]`

```nim
import std/options

proc tryAdvance(s: A): Option[B] {.transition.} =
  some(B(Flow(s)))
```

The pragma unwraps `Option[B]` to `B` and verifies `A -> B`.

### `Future[T]` (async)

```nim
import chronos

proc connect(c: Disconnected): Future[Connecting] {.async, transition.} =
  return Connecting(Socket(c))
```

Both pragma orderings — `{.async, transition.}` and
`{.transition, async.}` — produce identical signature AST from the
pragma's perspective, so both work. `{.transition, async.}` is
recommended for forward-compatibility with future body-level analysis.

### `Future[Result[T, E]]`

The most common async-with-error shape:

```nim
proc send(
    p: PreChecked
): Future[Result[SentUnacked, SendError]] {.async, transition.} =
  return ok(SentUnacked(Message(p)))
```

The pragma walks `Future -> Result -> SentUnacked` and validates
`PreChecked -> SentUnacked`.

## Registering Your Own Wrapper

Mark the type with `{.transparentWrapper.}` (cosmetic), then register
it at compile time:

```nim
type MyBox*[T] {.transparentWrapper.} = object
  inner: T

static:
  registerTransparentWrapper("MyBox")

# Now this validates the A -> B edge through MyBox:
proc advance(a: A): MyBox[B] {.transition.} =
  MyBox[B](inner: B(Flow(a)))
```

### The First-Generic-Argument Contract

Registered wrappers MUST put the wrapped state type at the **first**
generic-argument position. This matches the built-in seeds:

| Wrapper | Shape | State position |
|---------|-------|----------------|
| `Result[T, E]` | `T` is state, `E` is error | First |
| `Option[T]` | `T` is state | First |
| `Future[T]` | `T` is state | First |
| `MyBox[T]` | Your wrapper | First |

For a wrapper like `Container[Metadata, State]` where the state is at
position 1, do NOT register it. Use a non-transparent wrapper and
validate the transition at the call site instead.

## Opting Out: Local Types That Shadow a Built-in

If your project defines its own generic type that happens to share a
name with a built-in wrapper (e.g., a local `Result` type used as a
typestate state), call `unregisterTransparentWrapper` near the
typestate declaration:

```nim
static:
  unregisterTransparentWrapper("Result")

type
  Flow = object
  Pending = distinct Flow
  Result = distinct Flow  # local state, shadows the wrapper name

typestate Flow:
  states Pending, Result
  transitions:
    Pending -> Result

proc finish(p: Pending): Result {.transition.} =
  Result(Flow(p))
```

Without the `unregisterTransparentWrapper("Result")` call, the pragma
would try to unwrap `Result` as a wrapper and fail (or silently do the
wrong thing, depending on whether the local `Result` is generic).

## API

### `{.transparentWrapper.}`

Cosmetic marker pragma. Applying it to a generic type does NOT
register the wrapper; it documents intent and pairs with an explicit
`registerTransparentWrapper(...)` call. The actual registration is
always a compile-time `static:` block.

### `registerTransparentWrapper(name: string)`

Register a wrapper type as transparent for `{.transition.}` return
validation. Accepts either a bare name (`"MyBox"`) or a
module-qualified name (`"mymod.MyBox"`). Call inside a `static:`
block.

### `unregisterTransparentWrapper(name: string)`

Remove a wrapper from the registry. Use this to opt a built-in wrapper
out when your project has a same-name type that shouldn't be
unwrapped. Also callable inside a `static:` block.

### `isTransparentWrapper(name: string): bool`

Predicate. Checks both the given name and its extracted base name, so
module-qualified forms (`"results.Result"`) and bare forms
(`"Result"`) both hit the registry.

## Notes

- Wrapper matching is string-based: the registry stores names, not
  type symbols. A user-defined `Result` type in a project would
  silently get unwrapped unless you call
  `unregisterTransparentWrapper("Result")`.
- Cycle and depth protection: the unwrap walk detects wrapper cycles
  (`W1[W2[W1[X]]]`) and caps depth at 32.
- The pragma validates the outermost wrapper chain only. `seq[T]` is
  NOT a transparent wrapper — if you return `seq[B]` from source `A`,
  the pragma will report the literal `"seq"` and reject the edge.
