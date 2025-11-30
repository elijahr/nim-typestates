# nim-typestates

**Compile-time state machine validation for Nim.**

Make illegal states unrepresentable. Catch state transition bugs at compile time, not in production.

## The Problem

How many times have you seen bugs like these?

```nim
# BUG: Capturing payment before authorization
payment.capture()  # Runtime error: "Payment not authorized"

# BUG: Query on closed database connection
conn.execute("SELECT ...")  # Runtime error: "Connection closed"

# BUG: Shipping order before payment
order.ship()  # Lost merchandise, angry customers

# BUG: Robot arm moving without homing
arm.moveTo(100, 50, 20)  # CRASH into physical limits
```

These bugs pass code review, pass type checking, and explode in production.

## The Solution

With **nim-typestates**, these bugs are **compile-time errors**:

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
  echo "Authorizing $", p.Payment.amount
  result = Authorized(p.Payment)

proc capture(p: Authorized): Captured {.transition.} =
  echo "Capturing payment"
  result = Captured(p.Payment)

# Usage
let payment = Created(Payment(id: "pay_123", amount: 9999))
let authed = payment.authorize()
let captured = authed.capture()

# This is a COMPILE ERROR, not a runtime error:
# let bad = payment.capture()
#           ^^^^^^^^^^^^^^
# Error: type mismatch: got 'Created' but expected 'Authorized'
```

## Real-World Examples

nim-typestates shines in domains where **wrong order of operations = disaster**:

| Domain | What You Prevent |
|--------|-----------------|
| **Payment Processing** | Capturing before auth, double refunds |
| **Database Connections** | Query on closed connection, leak connections |
| **HTTP Clients** | Read response before sending request |
| **OAuth Flows** | API calls without authentication |
| **Hardware Control** | Moving robot before homing, motor damage |
| **Order Fulfillment** | Ship before payment, double-ship |
| **Document Workflow** | Publish without approval, edit published |

See the [`examples/`](examples/) directory for complete, runnable examples.

## Installation

```bash
nimble install nim_typestates
```

Or add to your `.nimble` file:

```nim
requires "nim_typestates >= 0.1.0"
```

## Quick Start

### 1. Define your base type and states

```nim
import nim_typestates

type
  File = object
    path: string
    fd: int

  Closed = distinct File
  Open = distinct File
```

### 2. Declare the typestate

```nim
typestate File:
  states Closed, Open
  transitions:
    Closed -> Open
    Open -> Closed
```

### 3. Implement transitions

```nim
proc open(f: Closed, path: string): Open {.transition.} =
  var file = f.File
  file.path = path
  file.fd = 1  # In reality: posix.open(path)
  result = Open(file)

proc close(f: Open): Closed {.transition.} =
  # posix.close(f.File.fd)
  result = Closed(f.File)
```

### 4. Implement non-transition operations

```nim
proc read(f: Open, n: int): string {.notATransition.} =
  # Can only read an Open file
  result = "data"

proc write(f: Open, data: string) {.notATransition.} =
  # Can only write to an Open file
  discard
```

### 5. Use it!

```nim
var f = Closed(File())
let opened = f.open("/etc/passwd")
let data = opened.read(100)
let closed = opened.close()

# Compile errors:
# f.read(100)        # Can't read Closed file
# opened.open("x")   # Can't open already-Open file
# closed.write("x")  # Can't write to Closed file
```

## Features

- **Compile-time validation**: Invalid transitions fail at compile time
- **Helpful error messages**: Shows valid transitions when you make a mistake
- **Branching transitions**: `Open -> Closed | Error`
- **Wildcard transitions**: `* -> Closed` (any state can transition)
- **Generated helpers**: Enum type, union type, `state()` procs
- **GraphViz export**: Visualize your state machines
- **Zero runtime overhead**: All checks happen at compile time

## Strict by Default

nim-typestates uses safe defaults:

- **strictTransitions = true** - All procs on states must be marked `{.transition.}` or `{.notATransition.}`
- **isSealed = true** - External modules can only add read-only operations

```nim
typestate Payment:
  # Both flags default to true
  states Created, Captured
  transitions:
    Created -> Captured

proc capture(p: Created): Captured {.transition.} = ...
proc amount(p: Created): int {.notATransition.} = ...
proc oops(p: Created): int = ...  # ERROR: unmarked!
```

## Verification

Run full-project verification:

```bash
nimble verify
```

Add to CI:

```yaml
- run: nimble verify
```

See [Strict Mode](docs/guide/strict-mode.md) and [Verification](docs/guide/verification.md) for details.

## Documentation

- [Getting Started](https://elijahr.github.io/nim-typestates/guide/getting-started/)
- [DSL Reference](https://elijahr.github.io/nim-typestates/guide/dsl-reference/)
- [Examples](https://elijahr.github.io/nim-typestates/guide/examples/)
- [API Reference](https://elijahr.github.io/nim-typestates/api/)

## How It Works

nim-typestates uses Nim's macro system to:

1. Parse the `typestate` DSL at compile time
2. Register valid transitions in a compile-time registry
3. Validate `{.transition.}` procs against declared transitions
4. Generate helpful types (enum, union) for runtime state inspection

The `distinct` types encode state in the type system, making invalid operations type errors.

## License

MIT
