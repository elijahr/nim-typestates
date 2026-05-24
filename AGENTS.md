# AGENTS.md — typestates

Guidance for AI assistants (and humans) contributing to nim-typestates.

## Pattern Signals from v0.9.0

### Pattern signal: the Green Mirage (over-conservative skip predicates)

When a verifier (or analyzer, or any default-deny / default-allow
classifier) emits a false-fire on a canonical shape, the tempting fix
is to add a skip predicate that exempts the shape's *category*:

```nim
for tp in params:
  if tp.isSink: continue   # avoid the false-fire on `result = Dst(s.Base)`
  analyze(tp)
```

This is the **Green Mirage**: tests go green, fixtures go green,
examples run clean — but the skip silently exempts an entire category
from analysis. Any real soundness gap in the exempted category now
passes review.

Observed in typestates v0.9.0 r9 → r14: an `if isSink: continue`
introduced to suppress a single false-fire on canonical sink-consume
shapes survived 4 review rounds while masking the gap on every
sink-T transition proc that failed to consume. The fix was to revert
the skip and improve the under-recognition that caused the original
false-fire (dot-call recognition in `extractTrackedLocal`).

#### Rule

When introducing a default-deny / skip / continue predicate to a
verifier or analyzer:

1. **Identify the under-recognition.** What shape did the verifier
   fail to model that caused the false-fire?
2. **Estimate the blast radius.** What real errors in the same
   category does the predicate now exempt? Write at least one
   negative fixture that the skip would silently pass.
3. **Prefer improving recognition over skipping.** If the under-
   recognition can be fixed at the call-shape / AST / type-info
   layer, do that. The skip is the last resort, not the first.
4. **If you must skip, document the exemption.** A comment naming
   the exempted shape and the planned recognition improvement is
   load-bearing — it makes the skip removable when the recognition
   lands.

## Pattern Signals from v0.9.3

### Pattern signal: pragma surface ambiguity (`{.kwarg: value.}` sibling vs `{.pragma(spec).}` call form)

When attaching a new metadata value to an existing pragma, Nim offers two
surfaces that *look* equally idiomatic but are parsed differently:

```nim
# (a) call/spec form — argument carried inside the pragma's own parens/colon
proc `=destroy`(h: var Halfopen) {.destructorTransition: Halfopen -> Closed.} =
  discard

# (b) sibling form — a separate pragma name listed alongside
proc lock(f: Open): Locked {.transition, transitionError: "msg".} =
  Locked(f)
```

During the v0.9.3 `transitionError` work, the natural first instinct was to
fold the message into the existing call/spec surface
(`{.transition(transitionError: "msg").}`, by analogy to the
`{.destructorTransition: T -> U.}` colon-spec form). That analogy does not
hold: `destructorTransition` carries its `T -> U` payload because
`destructorTransitionCore` (`src/typestates/pragmas.nim`) is a dedicated
dispatcher that interprets the colon argument as a transition spec — it is
not a generic kwarg slot. Extending it to also accept an arbitrary kwarg
would mean threading kwarg parsing through that dispatcher.

The v0.9.3 implementation took the cheaper, orthogonal route — the **sibling
form (b)**: a no-op marker pragma
`template transitionError*(msg: string) {.pragma.}`
(`src/typestates/pragmas.nim:84`) plus a helper
`extractTransitionErrorPragma*`
(`src/typestates/pragmas.nim:141`) that scans the host proc's `nnkPragma`
node for a sibling `transitionError: "msg"` entry and enforces the
static-string-literal constraint. Both the `transition` and
`destructorTransition` macros call the extractor
(`src/typestates/pragmas.nim:688`, `:1005`).

The ambiguity is invisible to a user reading either form — both are valid
Nim pragma syntax. The cost of guessing wrong is one
brief-author → implementer round-trip; cheap when caught at the
implementer-pre-flight stage, more expensive if a wrong-form assumption
ships into a downstream consumer's brief.

#### Rule

When proposing a new pragma parameter (for typestates or for any consumer
of the typestates pragma surface):

1. **Verify the parser path before assuming a surface.** Does the existing
   pragma macro accept a generic kwarg, or only its own positional /
   colon-spec payload? When unsure, compile-only a 3-line throwaway that
   uses the proposed syntax — a binary signal in under 30 seconds.
2. **Document the chosen form** in the pragma's own docstring and in the
   user-facing guide. Do not rely on consumers reasoning by analogy from a
   neighbouring pragma.
3. **When briefing downstream work that depends on a new pragma surface,**
   include the verified syntax verbatim in the brief's pre-flight section,
   not just a prose description of the semantic.

### Pattern signal (finding): `pkUnmarked` external-module path in `verify.nim` appears unreachable

`src/typestates/verify.nim` defines a `pkUnmarked` proc kind
(`verify.nim:18`, "No pragma specified") and `verifyTypestatesImpl` guards a
block on it (`verify.nim:2054`, `if procInfo.kind == pkUnmarked:`). Inside
that block, two diagnostics fire for unmarked procs operating on a typestate
state: a `strictTransitions` error (`verify.nim:2062-2067`) and an
**external-module** error (`verify.nim:2069-2075`,
"Unmarked proc ... from external module").

The live cross-module-transition prohibition for *`{.transition.}`-marked*
procs is enforced elsewhere — in `pragmas.nim` at transition-macro expansion
time (`src/typestates/pragmas.nim:742-751`, "Cannot define transition on
typestate ... from external module"). That `pragmas.nim` check has existed
since v0.4.0; the `verify.nim` `pkUnmarked` block was added later in v0.9.0
(verified via `git log -L`). So this is **not** a case of enforcement
"moving" from `verify.nim` to `pragmas.nim`; they target different proc
kinds, and `pragmas.nim` predates the `verify.nim` block.

What the source shows: `registerProc` is only ever called with
`kind: pkTransition` (`pragmas.nim:901`) and `kind: pkDestructorTransition`
(`pragmas.nim:1212`). No call site anywhere in `src/` or `tests/` ever
constructs a `RegisteredProc` with `kind: pkUnmarked`. Since the only place
`pkUnmarked` is read is the `if procInfo.kind == pkUnmarked:` guard, and no
producer ever sets that kind, the entire block (including the external-module
path at `verify.nim:2069-2075`) appears unreachable at the
source-registration level.

This finding surfaced during a downstream (lockfreequeues v5.0.0 wave) F.3.5
deliberate-negative cross-module containment test. That test exercised exactly
**one** cross-module case (a proc declaring `{.transition.}` on a typestate
state from outside the typestate's declaration module) and observed that the
diagnostic came from the `pragmas.nim` path, not the `verify.nim` path. A
single exercised case plus the static observation above is strong evidence,
but **does not prove universal deadness** — there may be a registration or
combination not present in the current test matrix.

A secondary, lower-stakes dimension: a downstream brief sequence cited
`verify.nim:2069-2074` as the "live" cross-module check location. The cite
was off by the live/historical distinction (the live `{.transition.}` check
is in `pragmas.nim`) and by line range (the block is `2069-2075`). It caused
no functional issue — the F.3.5 substring assertion matches the user-visible
message text, which is identical regardless of which path emitted it — but a
future reader of that test would chase a stale reference.

#### Resolution (REMOVED in v0.9.3)

The sweep below was completed during v0.9.3 code review and the dead
`pkUnmarked` guard block was **removed in v0.9.3** (Path A), not deferred
to v0.10. The decision and its rationale:

1. **Unreachability confirmed.** Cross-referencing the `pkUnmarked` block
   against every `registerProc` call site and `RegisteredProc` constructor
   showed only `kind: pkTransition` (`pragmas.nim:901`) and
   `kind: pkDestructorTransition` (`pragmas.nim:1212`) producers; no call
   site anywhere in `src/` or `tests/` constructs a `RegisteredProc` with
   `kind: pkUnmarked`. The guard was therefore structurally unreachable.
2. **Removed (Path A):** the `pkUnmarked` guard in `verifyTypestatesImpl`
   and its two diagnostics were deleted. The `pkUnmarked` enum value
   (`verify.nim:18`) was **kept** — it remains a meaningful `ProcKind`
   classification ("No pragma specified") and is part of the exported
   `ProcKind*` public API surface; pruning it would be a public-API change
   beyond the dead-code excision.
3. **Cite hygiene:** when a brief or review references a typestates
   surface location (`file:line`), verify the cite against the live path
   empirically (a `grep` + `git log -L`), not by recall.
