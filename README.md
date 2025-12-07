# nim-typestates

[![CI](https://github.com/elijahr/nim-typestates/actions/workflows/ci.yml/badge.svg)](https://github.com/elijahr/nim-typestates/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/docs-latest-blue.svg)](https://elijahr.github.io/nim-typestates/)
[![Release](https://img.shields.io/github/v/release/elijahr/nim-typestates)](https://github.com/elijahr/nim-typestates/releases/latest)
[![License](https://img.shields.io/github/license/elijahr/nim-typestates)](LICENSE)
[![Nim](https://img.shields.io/badge/Nim-2.2%2B-yellow.svg)](https://nim-lang.org)

Compile-time state machine validation for Nim.

## Overview

nim-typestates encodes state machines in Nim's type system. Invalid state transitions become compile-time errors instead of runtime bugs.

```nim
import typestates

type
  Payment = object
    id: string
    amount: int
  Created = distinct Payment
  Authorized = distinct Payment
  Captured = distinct Payment

typestate Payment:
  states Created, Authorized, Captured
  transitions:
    Created -> Authorized
    Authorized -> Captured

proc authorize(p: Created): Authorized {.transition.} =
  result = Authorized(p.Payment)

proc capture(p: Authorized): Captured {.transition.} =
  result = Captured(p.Payment)

# Valid usage
let payment = Created(Payment(id: "pay_123", amount: 9999))
let authed = payment.authorize()
let captured = authed.capture()

# Compile error: type mismatch, got 'Created' but expected 'Authorized'
# let bad = payment.capture()
```

## Guarantees

The `typestate` macro and `{.transition.}` pragma enforce state machine
rules at compile time. A program that compiles has been verified by the
compiler to contain no invalid state transitions.

### Verified at compile time

- **Protocol adherence**: Operations are only callable in valid states
- **Transition validity**: All `{.transition.}` procs follow declared paths
- **State exclusivity**: Each object occupies exactly one state

### Not verified

- **Functional correctness**: The implementation of each proc
- **Specification accuracy**: Whether the declared state machine matches
  the intended real-world protocol

The compiler verifies that your code follows the declared protocol.
It does not verify that the protocol itself is correct.

## Installation

```bash
nimble install typestates
```

Or add to your `.nimble` file:

```nim
requires "typestates >= 0.1.0"
```

## Usage

### Define states as distinct types

```nim
import typestates

type
  File = object
    path: string
    fd: int
  Closed = distinct File
  Open = distinct File
```

### Declare valid transitions

```nim
typestate File:
  states Closed, Open
  transitions:
    Closed -> Open
    Open -> Closed
```

### Implement transitions

```nim
proc open(f: Closed, path: string): Open {.transition.} =
  var file = f.File
  file.path = path
  file.fd = 1
  result = Open(file)

proc close(f: Open): Closed {.transition.} =
  result = Closed(f.File)
```

### Mark non-transitions

```nim
proc read(f: Open, n: int): string {.notATransition.} =
  result = "data"

proc write(f: Open, data: string) {.notATransition.} =
  discard
```

## Key Features

| Feature | Description |
|---------|-------------|
| **Compile-time validation** | Invalid transitions are compilation errors |
| **Zero runtime cost** | All validation happens at compile time |
| **Branching transitions** | `Open -> (Closed \| Error) as Result` |
| **Wildcard transitions** | `* -> Closed` (any state can transition) |
| **Generic typestates** | `Container[T]` with states like `Empty[T]`, `Full[T]` |
| **Cross-type bridges** | Transition between different typestates |
| **Visualization** | Export to GraphViz DOT, PNG, SVG |
| **CLI tool** | Project-wide verification |
| **Strict mode** | Require explicit marking of all state operations |
| **Sealed typestates** | Control external module access |

### Cross-Type Bridges

Model resource transformation and protocol handoff between typestates:

```nim
import typestates
import ./session

typestate AuthFlow:
  states Pending, Authenticated, Failed
  transitions:
    Pending -> Authenticated
    Pending -> Failed
  bridges:
    Authenticated -> Session.Active
    Failed -> Session.Guest

# Bridge implementation
converter toSession(auth: Authenticated): Active {.transition.} =
  Active(Session(userId: auth.AuthFlow.userId))
```

Bridges are validated at compile time and shown in visualization.

## CLI Tool

Verify typestate rules across your project:

```bash
typestates verify src/
```

### Visualization

Generate state machine diagrams from your code:

```bash
# Generate SVG
typestates dot src/ | dot -Tsvg -o states.svg

# Generate PNG
typestates dot src/ | dot -Tpng -o states.png

# Minimal output for custom styling
typestates dot --no-style src/ > states.dot
```

<p align="center">
  <img src="https://raw.githubusercontent.com/elijahr/nim-typestates/main/docs/assets/images/generated/multi.svg" alt="State Machine Visualization" width="600">
</p>

## Documentation

- [Getting Started](https://elijahr.github.io/nim-typestates/latest/guide/getting-started/)
- [DSL Reference](https://elijahr.github.io/nim-typestates/latest/guide/dsl-reference/)
- [Cross-Type Bridges](https://elijahr.github.io/nim-typestates/latest/guide/bridges/)
- [Generic Typestates](https://elijahr.github.io/nim-typestates/latest/guide/generics/)
- [Formal Guarantees](https://elijahr.github.io/nim-typestates/latest/guide/formal-guarantees/)
- [Examples](https://elijahr.github.io/nim-typestates/latest/guide/examples/)
- [API Reference](https://elijahr.github.io/nim-typestates/latest/api/)

## References

- [Typestate Pattern in Rust](https://cliffle.com/blog/rust-typestate/)
- [typestate crate for Rust](https://github.com/rustype/typestate)
- [Plaid Language](http://www.cs.cmu.edu/~aldrich/plaid/)
- [Typestate: A Programming Language Concept (Strom & Yemini, 1986)](https://doi.org/10.1109/TSE.1986.6312929)

## License

MIT
