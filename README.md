# nim-typestates

[![CI](https://github.com/elijahr/nim-typestates/actions/workflows/ci.yml/badge.svg)](https://github.com/elijahr/nim-typestates/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/docs-latest-blue.svg)](https://elijahr.github.io/nim-typestates/)
[![Release](https://img.shields.io/github/v/release/elijahr/nim-typestates)](https://github.com/elijahr/nim-typestates/releases/latest)
[![License](https://img.shields.io/github/license/elijahr/nim-typestates)](LICENSE)
[![Nim](https://img.shields.io/badge/Nim-2.2%2B-yellow.svg)](https://nim-lang.org)

Compile-time state machine verification for Nim. Encode a protocol — payment lifecycles, file handles, connection states — in the type system, and the compiler refuses to build code that calls operations in the wrong state.

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

proc authorize(p: sink Created): Authorized {.transition.} =
  Authorized(Payment(p))

proc capture(p: sink Authorized): Captured {.transition.} =
  Captured(Payment(p))

proc main() =
  let payment = Created(Payment(id: "pay_123", amount: 9999))
  let authed = payment.authorize()
  let captured = authed.capture()
  echo captured.Payment.id

  # payment.capture()  # type mismatch: got 'Created' but expected 'Authorized'

main()
```

The wrapper `proc main()` is required because typestate values can't be lifted to module scope under the default `consumeOnTransition = true` — the `=dup` hook is disabled, and module-scope `let` bindings would fail to compile.

## Installation

```bash
nimble install typestates
```

Or pin it in your `.nimble` file:

```nim
requires "typestates >= 0.4.0"
```

Requires Nim 2.2 or newer. If you're on Nim 2.2.x older than 2.2.8 and using ARC/ORC with `static` generic parameters, see the note below on a known codegen bug.

## What you get from the compiler

Once you've declared a typestate and marked your procs with `{.transition.}`, the compiler enforces three things:

- Each transition proc moves between states the way you declared. A proc that claims to take an `Authorized` and return a `Captured` cannot quietly become a transition from `Created`.
- Operations on a state are only callable when a value is in that state. `capture(p)` won't compile if `p` is `Created`.
- A value occupies one state at a time. The distinct types make it impossible to hold a `Captured` and an `Authorized` view of the same object simultaneously.

What the compiler can't check is whether your declared state machine matches reality. If your spec says `Authorized -> Captured` is allowed but your business rules actually forbid it after 7 days, that's a separate problem.

To enable state-aware error messages on transition misuse, end your module with `verifyTypestates()`. See [error handling](docs/guide/error-handling.md) for details.

There is one channel the type system cannot close: distinct types in Nim are syntactic, so `Captured(Payment(...))` will compile and forge a state value out of raw fields. v0.6 introduces `opaqueStates = true` as an opt-in CLI lint that flags these casts at `typestates verify` time, with caveats around cross-file resolution, generics, and `cast[T](...)` form. See [Cast Protection](docs/guide/cast-protection.md) for the full caught/missed table.

## Usage

### Branching transitions

A capture might succeed and settle, partially refund, or fully refund. Declare the alternatives as a union:

```nim
typestate Payment:
  states Captured, PartiallyRefunded, FullyRefunded, Settled
  transitions:
    Captured -> (PartiallyRefunded | FullyRefunded | Settled) as CaptureResult
```

The `as CaptureResult` names the union type so transition procs can return it. Callers then pattern-match (or use the generated discriminators) to know which branch they got.

### Async transitions

Pair `{.async, transition.}` with `Future[T]` returns. Bridging through `Result` works too:

```nim
proc authorize(p: sink Created): Future[Authorized] {.async, transition.} =
  await callPaymentGateway(p)
  return Authorized(Payment(p))

proc capture(p: sink Authorized): Future[Result[Captured, GatewayError]] {.async, transition.} =
  ...
```

Transparent wrappers (`Result[State, E]`, `Option[State]`, `Future[State]`) are recognized in return positions without losing the typestate guarantees.

### Generic typestates

States can carry type parameters, which is useful for typed buffers, containers, and similar:

```nim
type
  Container[T] = object
    items: seq[T]
  Empty[T] = distinct Container[T]
  Full[T] = distinct Container[T]

typestate Container[T]:
  states Empty[T], Full[T]
  transitions:
    Empty[T] -> Full[T]
```

### TypestateOp implicit effect

Every `{.transition.}` proc carries `TypestateOp` (defined in
`typestates/pragmas`, a `distinct object of RootEffect`) in its effect
tag set. Under `{.experimental: "strictEffects".}` you can declare
`{.forbids: [TypestateOp].}` on a region to statically assert "no
typestate transition reaches me — not directly, not transitively through
an untagged intermediate caller."

```nim
{.experimental: "strictEffects".}
import typestates

type
  EndpointBase = object
  Unbound = distinct EndpointBase
  Bound = distinct EndpointBase

typestate Endpoint:
  consumeOnTransition = false
  strictTransitions = false
  states Unbound, Bound
  transitions:
    Unbound -> Bound

proc bindIt(u: Unbound): Bound {.transition.} =
  Bound(EndpointBase(u))

proc pureRegion() {.forbids: [TypestateOp].} =
  discard  # OK: no transition reachable from here.

# proc badRegion() {.forbids: [TypestateOp].} =
#   let u = Unbound(EndpointBase())
#   discard bindIt(u)   # would fail to compile: TypestateOp forbidden here.

verifyTypestates()
```

The injection is **additive** and **idempotent**:

- **Additive.** If you already wrote `{.tags: [MyEffect].}` on a
  transition, the macro appends `TypestateOp` so the final list is
  `[MyEffect, TypestateOp]`. Your own tag is preserved.
- **Idempotent.** If you explicitly listed `TypestateOp` yourself, no
  duplicate is added. (The check uses `eqIdent` on `nnkIdent` / `nnkSym`;
  module-qualified forms like `pragmas.TypestateOp` or backtick-quoted
  forms produce a harmless duplicate entry — Nim de-duplicates them
  semantically. Will be widened in a follow-up.)

Outside `strictEffects` Nim performs no tag propagation, so existing
callers see zero behaviour change.

**Effects are orthogonal to typestates.** Typestates describe a value's
position in a state graph; effects describe what a proc can do. The
`TypestateOp` injection lets you assert the orthogonal property "this
region performs no state transitions" without forcing every author to
remember a separate marker pragma. Combined-pragma forms like
`{.transition, tags: [ProducerOp], gcsafe.}` work because the v0.10.0
AST verifier walks pragma nodes structurally (no text-scanner).

#### Note: user-supplied tags become an upper bound

When you write `{.transition, tags: [SomeNarrowTag].}`, the macro appends
`TypestateOp` (without `RootEffect`). Nim's `tags:` is an **upper bound**
on the proc's effect set, so if your transition body needs broader
effects (allocation, IO, etc.) you must add `RootEffect` yourself:

```nim
proc bindIt(u: Unbound): Bound
    {.transition, tags: [SomeNarrowTag, RootEffect], gcsafe.} =
  Bound(EndpointBase(u))
```

Bare `{.transition.}` procs get `{.tags: [TypestateOp, RootEffect].}`
synthesised by the macro for exactly this reason — `RootEffect` keeps
the bound permissive while `TypestateOp` keeps the `forbids:` check
load-bearing (`forbids` matches the literal `TypestateOp` tag, not its
ancestors).

### Cross-type bridges

If finishing one typestate hands control to another (auth flow into a session, for example), declare the bridge:

```nim
typestate AuthFlow:
  states Pending, Authenticated, Failed
  transitions:
    Pending -> Authenticated
    Pending -> Failed
  bridges:
    Authenticated -> Session.Active
    Failed -> Session.Guest

converter toSession(auth: Authenticated): Active {.transition.} =
  Active(Session(userId: auth.AuthFlow.userId))
```

Bridges show up in the generated diagrams alongside ordinary transitions.

## Features

- States as `distinct` types — no runtime tag, no runtime check, no runtime cost
- Branching unions (`A -> (B | C) as Result`) and wildcard sources (`* -> Closed`)
- Union source params: `proc cancel(o: Open | PartiallyFilled): Cancelling`
- Transparent wrappers in return types: `Result[State, E]`, `Option[State]`, `Future[State]`
- Async transitions via `{.async, transition.}`
- Generic typestates including states with `static` parameters
- Cross-type bridges between separate typestates
- Strict mode that requires every proc on a state to be marked `{.transition.}` or `{.notATransition.}`
- Opt-in cast-bypass lint via `opaqueStates = true` (CLI-only, warnings only)
- Sealed typestates that restrict transitions to the defining module
- Implicit `TypestateOp` effect tag on every `{.transition.}` proc, enabling `{.forbids: [TypestateOp].}` regions under `{.experimental: "strictEffects".}`
- A `typestates` CLI that verifies a project tree and exports diagrams

## CLI

The `typestates` binary verifies a directory and produces GraphViz output:

```bash
typestates verify src/

typestates dot src/ | dot -Tsvg -o states.svg
typestates dot src/ | dot -Tpng -o states.png
typestates dot --no-style src/ > states.dot   # unstyled, easier to theme
```

### CI integration

Run `typestates verify` in pre-commit hooks, GitHub Actions, or GitLab CI. The
v0.7 CLI exposes `--warnings-as-errors` for gating builds and `--format=github`
for inline PR annotations. See [CI Integration](https://elijahr.github.io/nim-typestates/latest/guide/ci-integration/)
for setup recipes and the documented JSON schema.

<p align="center">
  <img src="https://raw.githubusercontent.com/elijahr/nim-typestates/main/docs/assets/images/generated/multi.svg" alt="Generated typestate diagram showing multiple states and transitions" width="600">
</p>

## Known issue: Nim < 2.2.8 with `static` generics

If you use a `static` generic parameter (`Buffer[N: static int]`) with ARC, ORC, or AtomicARC on Nim 2.2.x before 2.2.8, you may hit a [codegen bug](https://github.com/nim-lang/Nim/issues/25341). The library detects the affected pattern at compile time and prints workarounds. The options, in rough order of preference:

1. Upgrade to Nim 2.2.8 or newer.
2. Compile with `--mm:refc` instead of ARC/ORC.
3. Add `consumeOnTransition = false` to the typestate (changes semantics — read the docs).
4. Make the base type inherit from `RootObj` and set `inheritsFromRootObj = true`.

Plain generics (`Container[T]`) are unaffected.

## Documentation

The full guide and API reference live at <https://elijahr.github.io/nim-typestates/>.

- [Getting started](https://elijahr.github.io/nim-typestates/latest/guide/getting-started/)
- [DSL reference](https://elijahr.github.io/nim-typestates/latest/guide/dsl-reference/)
- [Formal guarantees](https://elijahr.github.io/nim-typestates/latest/guide/formal-guarantees/)
- [Examples](https://elijahr.github.io/nim-typestates/latest/guide/examples/)
- [CI Integration](https://elijahr.github.io/nim-typestates/latest/guide/ci-integration/)
- [API reference](https://elijahr.github.io/nim-typestates/latest/api/)

The [`examples/`](examples/) directory in this repo has runnable versions of the examples used in the docs (payments, OAuth, hardware registers, document workflows, and others).

## Contributing

Fork, create a branch, run `nimble test` and `nimble compileExamples` before opening a PR. The full guide is in [CONTRIBUTING.md](CONTRIBUTING.md).

## Prior art

- [Typestate pattern in Rust](https://cliffle.com/blog/rust-typestate/) (Cliff Biffle)
- [`typestate` crate for Rust](https://github.com/rustype/typestate)
- [Plaid](http://www.cs.cmu.edu/~aldrich/plaid/), a research language with first-class typestate
- Strom & Yemini, ["Typestate: A programming language concept for enhancing software reliability"](https://doi.org/10.1109/TSE.1986.6312929) (1986) — the original paper

## License

MIT — see [LICENSE](LICENSE).
