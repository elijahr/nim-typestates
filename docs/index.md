# nim-typestates

Compile-time typestate validation for Nim.

## What is this?

**nim-typestates** is a Nim library that enforces state machine patterns at compile time. Define your valid states and transitions, and the compiler ensures your code follows them.

```nim
import typestates

type
  File = object
    path: string
  Closed = distinct File
  Open = distinct File

typestate File:
  states Closed, Open
  transitions:
    Closed -> Open
    Open -> Closed

proc open(f: Closed): Open {.transition.} =
  result = Open(f)

proc close(f: Open): Closed {.transition.} =
  result = Closed(f)

# This works:
let f = Closed(File(path: "/tmp/test"))
let opened = f.open()
let closed = opened.close()

# This won't compile - Open can't transition to Open!
# let bad = opened.open()
```

The compiler verifies that your code follows the declared protocol. If it
compiles, invalid state transitions are impossible. See
[Formal Guarantees](guide/formal-guarantees.md) for details.

## Why typestates?

Traditional runtime state machines have problems:

- **Runtime errors**: Invalid transitions cause crashes or bugs
- **Defensive code**: You write `if state == X` checks everywhere
- **Documentation drift**: State diagrams don't match code

Typestates solve this by encoding states in the type system:

- **Compile-time errors**: Invalid transitions don't compile
- **Self-documenting**: Types show valid operations
- **Zero runtime cost**: It's just types

## Features

- **Compile-time validation** - Invalid transitions fail at compile time with clear error messages
- **Branching transitions** - `Closed -> Open | Errored`
- **Wildcard transitions** - `* -> Closed` (any state can close)
- **Generated helpers** - `FileState` enum, `FileStates` union type
- **GraphViz export** - Visualize your state machine

## Installation

```bash
nimble install nim_typestates
```

Or add to your `.nimble` file:

```nim
requires "nim_typestates >= 0.1.0"
```

## Quick Links

- [Getting Started](guide/getting-started.md) - Tutorial walkthrough
- [DSL Reference](guide/dsl-reference.md) - Complete syntax documentation
- [Examples](guide/examples.md) - Real-world patterns
- [API Reference](api.md) - Generated API docs

## References

- [Typestate Pattern in Rust](https://cliffle.com/blog/rust-typestate/) - Excellent introduction to typestates
- [typestate crate for Rust](https://github.com/rustype/typestate) - Similar macro-based approach in Rust
- [Plaid Language](http://www.cs.cmu.edu/~aldrich/plaid/) - CMU's typestate-oriented programming language
- [Typestate: A Programming Language Concept (Strom & Yemini, 1986)](https://doi.org/10.1109/TSE.1986.6312929) - Original paper introducing typestates

## License

MIT
