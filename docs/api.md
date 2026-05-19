# API Reference

Auto-generated API documentation from source code.

## Main Module

::: typestates

---

## Submodules

### Types

Core type definitions.

::: typestates.types

---

### Parser

DSL parser for typestate blocks.

::: typestates.parser

---

### Registry

Compile-time typestate storage.

::: typestates.registry

**v0.9.0 additions** (also auto-documented above):

- `type AttachmentInfo*` — record of a `{.<TypestateName>: <InitialState>.}`
  binding (typestate name, initial state, declaredAt).
- `var typestateAttachments* {.compileTime.}: Table[string, AttachmentInfo]` —
  compile-time registry keyed by attached object type base name.
- `proc findAttachmentForType*(typeName: string): Option[AttachmentInfo]` —
  lookup helper used by `destructorTransitionCore` for path (b) source
  resolution.
- `proc addAttachment*(typeName: string, info: AttachmentInfo)` — internal
  register helper used by the per-typestate attachment-pragma macro.

---

### Pragmas

Pragma implementations for transition validation.

::: typestates.pragmas

**v0.9.0 additions** (also auto-documented above):

- `macro destructorTransition*(destrDef: untyped)` — single-arg form.
  Destination state inferred as the typestate's terminal-state set.
- `macro destructorTransition*(spec, destrDef: untyped)` — two-arg form.
  Destination state explicit via the `SrcState -> DstState` spec.
- `template skipCfgAnalysis*()` — opt out a single proc from the v0.9.0
  CFG analyzer pass.
- Per-typestate attachment pragma — auto-emitted by the `typestate` macro
  as `{.<TypestateName>: <InitialState>.}`, used on object type decls to
  bind a distinct-name type to a typestate.

See [Destructor Transitions](guide/destructor-transitions.md) and
[CFG Analyzer](guide/cfg-analyzer.md) for usage.

---

### Code Generation

Code generation for helper types.

::: typestates.codegen

---

### CLI

Command-line tool functionality.

::: typestates.cli
