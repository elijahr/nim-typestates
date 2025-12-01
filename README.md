# nim-typestates

Compile-time state machine validation for Nim.

## Overview

nim-typestates encodes state machines in Nim's type system. Invalid state transitions become compile-time errors instead of runtime bugs.

```nim
import nim_typestates

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

## Installation

```bash
nimble install nim_typestates
```

Or add to your `.nimble` file:

```nim
requires "nim_typestates >= 0.1.0"
```

## Usage

### Define states as distinct types

```nim
import nim_typestates

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

## Features

- **Compile-time validation** — Invalid transitions fail to compile
- **Generic types** — `Container[T]` with states like `Empty[T]`, `Full[T]`
- **Branching transitions** — `Open -> Closed | Error`
- **Wildcard transitions** — `* -> Closed` (any state can transition)
- **Self-transitions** — `Open -> Open` for state-preserving operations
- **Strict mode** — All procs on states must be explicitly marked
- **Sealed typestates** — External modules can only add read-only operations
- **CLI tool** — Project-wide verification and GraphViz export
- **Zero runtime cost** — All validation happens at compile time

## CLI Tool

Verify typestate rules across your project:

```bash
nim-typestates verify src/
```

Generate GraphViz diagrams:

```bash
nim-typestates dot src/ | dot -Tpng -o states.png
```

## Documentation

- [Getting Started](https://elijahr.github.io/nim-typestates/guide/getting-started/)
- [DSL Reference](https://elijahr.github.io/nim-typestates/guide/dsl-reference/)
- [Generic Typestates](https://elijahr.github.io/nim-typestates/guide/generics/)
- [Examples](https://elijahr.github.io/nim-typestates/guide/examples/)
- [API Reference](https://elijahr.github.io/nim-typestates/api/)

## References

- [Typestate Pattern in Rust](https://cliffle.com/blog/rust-typestate/)
- [typestate crate for Rust](https://github.com/rustype/typestate)
- [Plaid Language](http://www.cs.cmu.edu/~aldrich/plaid/)
- [Typestate: A Programming Language Concept (Strom & Yemini, 1986)](https://doi.org/10.1109/TSE.1986.6312929)

## License

MIT
