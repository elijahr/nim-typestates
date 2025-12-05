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
- **Branching transitions** - `Closed -> Open | Errored as OpenResult` with user-named branch types
- **Wildcard transitions** - `* -> Closed` (any state can close)
- **Generated helpers** - `FileState` enum, `FileStates` union type, branch constructors
- **Cross-typestate bridges** - Connect independent state machines
- **GraphViz export** - Visualize your state machine

## Installation

```bash
nimble install typestates
```

Or add to your `.nimble` file:

```nim
requires "typestates >= 0.1.0"
```

## Quick Links

- [Getting Started](guide/getting-started.md) - Tutorial walkthrough
- [DSL Reference](guide/dsl-reference.md) - Complete syntax documentation
- [Examples](guide/examples.md) - Real-world patterns
- [API Reference](api.md) - Generated API docs

## References

### Foundational Papers

- [Typestate: A Programming Language Concept (Strom & Yemini, 1986)](https://doi.org/10.1109/TSE.1986.6312929) - The original paper introducing typestates as a compile-time mechanism for tracking object state
- [Typestates for Objects (Aldrich et al., 2009)](https://www.cs.cmu.edu/~aldrich/papers/classic/tse12-typestate.pdf) - Extends typestates to object-oriented programming with practical implementation strategies

### Tutorials and Introductions

- [The Typestate Pattern in Rust](https://cliffle.com/blog/rust-typestate/) - Accessible introduction to encoding typestates using Rust's type system
- [Typestate Analysis (Wikipedia)](https://en.wikipedia.org/wiki/Typestate_analysis) - Overview of typestate analysis concepts and history
- [Formal Verification (Wikipedia)](https://en.wikipedia.org/wiki/Formal_verification) - Background on formal methods that typestates relate to

### Related Projects

- [typestate crate for Rust](https://github.com/rustype/typestate) - Procedural macro approach to typestates in Rust, similar design philosophy to nim-typestates
- [Plaid Programming Language](http://www.cs.cmu.edu/~aldrich/plaid/) - Research language from CMU with first-class typestate support built into the language

## License

MIT
