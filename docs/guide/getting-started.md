# Getting Started

This guide walks through building a typestate-validated file handle from scratch.

## Prerequisites

- Nim 2.0 or later
- Basic familiarity with Nim's type system

## Installation

```bash
nimble install typestates
```

!!! warning "Nim < 2.2.8 with Static Generics"

    If you use `static` generic parameters (e.g., `Buffer[N: static int]`) with ARC/ORC/AtomicARC,
    you may hit a [Nim codegen bug](https://github.com/nim-lang/Nim/issues/25341) fixed in Nim 2.2.8.
    The library detects this and shows workarounds. Options:

    1. Make your base type inherit from `RootObj` and add `inheritsFromRootObj = true`
    2. Upgrade to Nim >= 2.2.8
    3. Add `consumeOnTransition = false` to your typestate
    4. Use `--mm:refc` instead of ARC/ORC

    Regular generics (`Container[T]`) are not affected.

## Step 1: Define Your Base Type

Start with a regular object type that holds your data:

```nim
type
  File = object
    path: string
    handle: int  # OS file descriptor
```

## Step 2: Define State Types

Create distinct types for each state. Using `distinct` ensures the compiler treats them as different types:

```nim
type
  File = object
    path: string
    handle: int

  Closed = distinct File
  Open = distinct File
```

Now `Closed` and `Open` are incompatible types - you can't pass a `Closed` where an `Open` is expected.

## Step 3: Declare the Typestate

Import the library and declare valid transitions:

```nim
import typestates

type
  File = object
    path: string
    handle: int
  Closed = distinct File
  Open = distinct File

typestate File:
  states Closed, Open
  transitions:
    Closed -> Open
    Open -> Closed
```

This tells the compiler:

- `File` has two states: `Closed` and `Open`
- `Closed` can transition to `Open`
- `Open` can transition to `Closed`
- No other transitions are valid

## Step 4: Implement Transitions

Use the `{.transition.}` pragma to mark state-changing procs:

```nim
proc open(f: Closed, path: string): Open {.transition.} =
  ## Open a closed file, returning it in the Open state.
  var file = f.File  # Access underlying File
  file.path = path
  file.handle = 1  # Pretend we opened it
  result = Open(file)

proc close(f: Open): Closed {.transition.} =
  ## Close an open file, returning it in the Closed state.
  var file = f.File
  file.handle = 0  # Pretend we closed it
  result = Closed(file)
```

The `{.transition.}` pragma validates at compile time that:

1. The input type (`Closed` or `Open`) is a registered state
2. The return type is a valid transition target
3. The transition is declared in the typestate block

## Step 5: Use It

```nim
# Create a file in the Closed state
var f = Closed(File(path: "", handle: 0))

# Open it - returns Open type
let opened = f.open("/tmp/example.txt")

# Close it - returns Closed type
let closed = opened.close()

# This won't compile!
# let bad = opened.open("/other.txt")
# Error: Undeclared transition: Open -> Open
```

## What Happens on Invalid Transitions?

If you try to implement an undeclared transition:

```nim
proc lock(f: Open): Locked {.transition.} =
  discard
```

You get a compile-time error:

```
Error: Undeclared transition: Open -> Locked
  Typestate 'File' does not declare this transition.
  Valid transitions from 'Open': @["Closed"]
  Hint: Add 'Open -> Locked' to the transitions block.
```

## Generated Helpers

The `typestate` macro generates some useful types:

### State Enum

```nim
type FileState* = enum
  fsClosed, fsOpen
```

### Union Type

```nim
type FileStates* = Closed | Open
```

### State Procs

```nim
proc state*(f: Closed): FileState = fsClosed
proc state*(f: Open): FileState = fsOpen
```

Use them for runtime inspection when needed:

```nim
proc describe[S: FileStates](f: S): string =
  case f.state
  of fsClosed: "File is closed"
  of fsOpen: "File is open"
```

## Next Steps

- [DSL Reference](dsl-reference.md) - Learn about branching, wildcards, and more
- [Examples](examples.md) - See real-world patterns
- [Error Handling](error-handling.md) - Model errors as states

For details on what the compiler verifies, see [Formal Guarantees](formal-guarantees.md).
