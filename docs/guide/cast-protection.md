# Cast Protection

Typestates in nim-typestates are `distinct` types over a base value. That gives
zero-cost compile-time enforcement on transition signatures, but it leaves one
back door wide open: a `distinct` type's name is also a syntactic cast.

## The bypass

Given a typestate:

```nim
typestate Payment:
  states Created, Authorized, Captured
  initial Created
  transitions:
    Created -> Authorized
    Authorized -> Captured
```

The macro generates `Created`, `Authorized`, and `Captured` as `distinct
Payment` types. Nim allows any distinct type to be constructed by calling its
name on the base value. So this compiles:

```nim
# Nowhere did Created ever go through authorize() or capture().
# This is a forged Captured value.
let stolen = Captured(Payment(id: "x", amount: 1))
settle(stolen)  # accepted by the type system
```

The transition graph is bypassed entirely. The base `Payment` was never an
`Authorized`, but the cast manufactures a `Captured` from raw fields.

This is not a bug in the macro; it is how `distinct` works. The macro side
cannot close this hole without breaking legitimate construction (initial-state
values have to be built somewhere). What the macro can do is help the CLI find
the bypass.

## Opting in

Add `opaqueStates = true` to a typestate declaration:

```nim
typestate Payment:
  opaqueStates = true
  states Created, Authorized, Captured
  initial Created
  transitions:
    Created -> Authorized
    Authorized -> Captured
```

Default is `false`. Existing code is unaffected unless you set the flag.

The lint runs as part of `typestates verify`. There is no separate command and
no separate output stream; warnings appear in the standard verify report.

## What gets caught

| Construct | Outcome |
|---|---|
| `Captured(payment)` outside any `{.transition.}` proc | WARNED |
| `payments.Captured(p)` (qualified call) | WARNED |
| `Captured(payment)` inside a `{.transition.}` proc body | allowed |
| `Created(Payment(...))` anywhere (initial state) | allowed |
| Construction inside `nkLambda` / `nkDo` blocks within a transition body | inherits transition status (allowed) |
| Construction inside a nested unmarked proc within a transition body | WARNED (separate scope) |

The rule is simple: non-initial state casts are only legal inside the body of a
proc literally marked `{.transition.}`. Everything else is a forged value.

## Limitations and known false-positive sources

The lint is opt-in for a reason. Several classes of input are not yet handled
in v0.6.

### Cross-file resolution

If you run `typestates verify <subset>` over a path that excludes the typestate
definition, the lint silently has no rules to apply for that typestate. There
is no error; the file simply produces no opaque-state findings.

Run verify over the project root, or over any path tree that includes the
typestate definitions. A subset run that excludes the definition module gives
you a clean report that proves nothing.

### Identifier collisions

A user-defined proc named the same as a state type will be flagged:

```nim
proc Captured(x: int): string = ...
let s = Captured(42)  # WARNED, but this is not a state cast
```

Workarounds:

- Rename the colliding identifier.
- Drop `opaqueStates = true` for that typestate.

A per-call suppression syntax is a v0.7 candidate.

### Pragma aliases and `{.push transition.}` blocks

The lint detects `{.transition.}` literally on each routine definition. Two
syntactically valid forms are not recognized in v0.6:

- `{.pragma: tx = transition.}` followed by `proc f(...) {.tx.} = ...`
- `{.push transition.}` ... `{.pop.}` blocks

Calls inside such procs will be flagged. Use the literal `{.transition.}`
pragma form on each routine to avoid false positives.

### Generic states

`Empty[int](items: ...)` (with an `nkBracketExpr` callee) is not flagged in
v0.6. Generic typestate construction goes through a different AST shape that
the lint does not yet inspect.

### `cast[T](...)` form

The Nim `cast` operator (`cast[Captured](payment)`) is not flagged in v0.6.
The lint only inspects call-syntax casts (`Captured(payment)`).

### Templates and macros

The lint reads source AST, not expansions.

- Calls inside template or macro bodies that construct opaque states ARE
  flagged at the body's source location.
- Calls passed as arguments to a macro (`logged(Captured(p))`) ARE flagged at
  the source argument site, before macro expansion.
- The expansion site itself is invisible to the lint.

If your template legitimately constructs opaque states, mark the call site or
move the construction into a `{.transition.}` proc.

## Why warnings, not errors

This is opt-in lint, not the type system. The macro-side typestate machinery
still gives you compile-time guarantees on transition signatures: a proc that
takes `Created` cannot be called with `Captured`, period. Cast bypass is a
separate channel that cannot be closed without breaking legitimate
initial-state construction.

The right place to enforce no-cast-bypass is CI. Promote the warnings to errors
there if you want hard enforcement. Do not break local builds for code that
compiles correctly under the type system.

## Configuration warning

If you set `opaqueStates = true` on a typestate without any `initial:` block,
and the macro infers no initials, the lint emits a one-time configuration
warning and skips that typestate. Without an initial state set, every cast
would be flagged, including the legitimate construction path.

To use the lint, declare your initial state(s) explicitly:

```nim
typestate Payment:
  opaqueStates = true
  states Created, Authorized, Captured
  initial Created       # required when opaqueStates = true
  transitions:
    Created -> Authorized
    Authorized -> Captured
```
