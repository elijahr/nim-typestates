# Destructor Transitions (v0.9.0)

The `{.destructorTransition.}` pragma marks a Nim `=destroy` hook as the
terminal transition of a typestate. Once registered, the
[CFG analyzer](cfg-analyzer.md) recognises any local of the source-state
type as auto-consumed at every scope exit (return, raise, fall-through):
Nim's destructor injection guarantees the transition fires.

## The Two Arities

`{.destructorTransition.}` has two overloads.

### Single-arg form

```nim
proc `=destroy`(f: var Open) {.destructorTransition.}
```

Destination state is **inferred** from the typestate's terminal-state set.
Prefer this form when the typestate declares exactly one terminal, or when
the destructor consumes via a `match` over the union of terminals.

### Two-arg form

```nim
proc `=destroy`(c: var Halfopen)
    {.destructorTransition: Halfopen -> Closed.}
```

Destination state is **explicit** via the `SrcState -> DstState` spec.
Prefer this form when:

- The typestate declares multiple terminals and the destructor targets a
  specific one.
- Local readability of the destination is load-bearing — readers see the
  edge at the destructor's declaration site without cross-referencing the
  typestate decl.
- You want symmetry with neighbouring `{.transition: A -> B.}` procs.

Both forms register the same `pkDestructorTransition` kind; they differ
only in how the destination is *expressed* and the CFG analyzer behaves
identically.

## Validation Rules

Every diagnostic below is emitted at compile time, attributed to the
`=destroy` decl site (or the spec node for two-arg-form errors). See
Appendix B of the design doc for full message templates.

| ID | Trigger |
|---|---|
| DT-001 | Pragma applied to something that is not a proc def. |
| DT-002 | Proc name is not `` `=destroy` ``. |
| DT-003 | Destructor takes the wrong number of params (must be 1, the `var self`). |
| DT-004 | Param is not `var T`. |
| DT-005 | Non-empty `raises` list. Destructors require `{.raises: [].}`; auto-injected if absent. |
| DT-006 | Param type is neither a registered typestate state nor a typestate-attached object type. |
| DT-007 | Typestate has no `terminal:` block. Destructors model terminal transitions and need a declared terminal. |
| DT-008 | Source type is already a terminal state (no transition possible). |
| DT-009 | Two-arg form: spec is not `nnkInfix(->, Src, Dst)`. |
| DT-010 | Two-arg form: SrcState mismatches the destructor's param type. |
| DT-011 | Two-arg form: DstState is not in the typestate's `terminalStates`. |
| DT-013 | Two-arg form, attached-object param: SrcState mismatches the attachment's initial state. |

`{.raises: [].}` is auto-injected if absent — `{.destructorTransition.}`
on its own produces the same outcome as `{.destructorTransition, raises: [].}`.

## Typestate Attachment for Distinct-Name Object Types

When the destructor's `var T` parameter is **not** itself a typestate
state — e.g. a generic wrapper holding the state as a field — bind the
type to its typestate via the typestate-attachment pragma:

```nim
typestate PinnedScopeContext:
  consumeOnTransition = false
  strictTransitions = false
  states PinnedScopeAlive, PinnedScopeDestroyed
  initial:
    PinnedScopeAlive
  terminal:
    PinnedScopeDestroyed
  transitions:
    PinnedScopeAlive -> PinnedScopeDestroyed

type PinnedScope* {.PinnedScopeContext: PinnedScopeAlive.} = object
  payload: int

proc `=destroy`(s: var PinnedScope) {.destructorTransition.} =
  discard
```

Without the attachment pragma, the CFG analyzer would not know that
`PinnedScope` is typestate-bearing and the destructor would fail with
DT-006.

**Same-name limitation.** The attachment pragma is only available when the
typestate name differs from the attached object type's name. By
established convention, single-name typestates pair with a same-named
object type (e.g., `typestate Resource:` + `type Resource = object`), and
Nim does not allow emitting a per-typestate marker macro under the same
identifier. The codegen detects this case, emits a compile-warning naming
the colliding typestate, and falls back to the existing
state-typed-param resolution path. Workaround: rename the typestate (e.g.
`ResourceContext`) and use the attachment pragma.

## Worked Example

```nim
import typestates

type
  FileHandle = object
    fd: int

  Open = distinct FileHandle
  Closed = distinct FileHandle

typestate FileLifecycle:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Closed

proc `=destroy`(f: var Open) {.destructorTransition.} =
  ## Bridges Open -> Closed at every scope exit.
  echo "  destructor closing fd ", f.FileHandle.fd

proc consume(o: sink Open): Closed {.transition.} =
  ## Explicit close. The destructor does NOT fire on `o` because `sink`
  ## moves ownership out of this scope.
  Closed(o.FileHandle)

proc run(early: bool) =
  var aux = Open(FileHandle(fd: 7))
  if early:
    return                    # destructor closes aux automatically
  discard consume(move aux)

verifyTypestates()
```

A full runnable version lives at
[`examples/destructor_transition_example.nim`](https://github.com/elijahr/nim-typestates/blob/main/examples/destructor_transition_example.nim).

## See Also

- [CFG Analyzer](cfg-analyzer.md) — exit-edge enforcement that
  destructor transitions satisfy.
- [Verification](verification.md) — `verifyTypestates()` overview.
