# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.9.0] - 2026-05-17

### Breaking (pre-1.0 latitude)

- **CFG analyzer enabled by default.** A new control-flow-graph pass
  inside `verifyTypestates()` rejects exit edges (return, raise,
  fall-through, discard, scope-escaping break/continue) that leave a
  typestate-bearing local in a non-terminal state. The analyzer tracks
  state transitions through call, assignment, var/let-init, and
  sink-consume positions for registered `{.transition.}` and
  `{.destructorTransition.}` procs, and resolves identifier shadowing
  innermost-first. Branch reconciliation rejects locals consumed in
  some branches but left non-terminal in others (CFG-002). Code that
  compiled and verified under 0.8.0 may newly fail verification under
  0.9.0 when the analyzer surfaces a latent early-return-out-of-typestate
  bug. This is a soft-breaking change covered by pre-1.0 SemVer 2.0 §4
  latitude; an empirical audit of two downstream consumers (50
  `{.transition.}` procs across nim-debra 0.8.0 + lockfreequeues 4.1.x)
  found 49/50 safe and 1 that needed the `{.skipCfgAnalysis.}` escape
  hatch. See [docs/guide/cfg-analyzer.md](docs/guide/cfg-analyzer.md)
  for the migration guide, recognized transition shapes, decision
  criteria, and the escape hatch.
- **`{.destructorTransition.}` required on typestate `=destroy` hooks.**
  Nim `=destroy` hooks for a typestate-bearing type that perform the
  terminal transition must declare `{.destructorTransition.}` so the CFG
  analyzer recognizes the auto-consumption at scope exits. Existing
  destructors that did not perform a transition are unaffected; existing
  destructors that did perform one were previously invisible to
  verification and now require the pragma. See
  [docs/guide/destructor-transitions.md](docs/guide/destructor-transitions.md).
- **Same-name typestate compile-warning.** When a typestate's name
  collides with the name of an object type in the same module (e.g.,
  `typestate Resource:` + `type Resource = object`), the per-typestate
  attachment-pragma macro cannot be emitted (Nim does not allow
  redefinition). Codegen now emits a `{.warning.}` at use-site naming the
  colliding typestate and suggesting a `<Name>Context` rename. Distinct-name
  typestates are unaffected. This is a documented constraint of the §3.7
  attachment pragma, not a regression: legacy same-name typestates that
  never used attachment continue to compile and verify unchanged.

### Added

- **`{.destructorTransition.}` pragma (two arities).**
    - Single-arg: `proc \`=destroy\`(f: var Open) {.destructorTransition.}`.
      Destination state inferred as the typestate's `terminalStates` set.
    - Two-arg: `proc \`=destroy\`(c: var Halfopen)
      {.destructorTransition: Halfopen -> Closed.}`. Destination state
      explicit; spec validated against the typestate graph.
    - Auto-injects `{.raises: [].}` when absent.
    - Compile-time diagnostic catalog: DT-001..DT-011, DT-013.
- **`{.skipCfgAnalysis.}` pragma.** Per-proc opt-out for the CFG
  analyzer. Use sparingly for verified false positives.
- **Typestate-attachment pragma.** Per-typestate macro emitted by the
  `typestate` macro of the form `{.<TypestateName>: <InitialState>.}`,
  applied to an object type declaration to bind that type to a typestate
  with an initial state. Only available when the typestate name differs
  from the attached object type (see Breaking above). Compile-time
  diagnostic catalog: TA-001..TA-004.
- **CFG analyzer diagnostic codes.** CFG-001 (missed terminal at exit
  edge), CFG-002 (branch reconciliation mismatch), CFG-003 (discard of
  non-terminal typestate value).
- **Public registry surface** in `src/typestates/registry.nim`:
  `type AttachmentInfo*`, `var typestateAttachments* {.compileTime.}`,
  `proc findAttachmentForType*`, `proc addAttachment*`.
- New documentation:
  [Destructor Transitions](docs/guide/destructor-transitions.md) and
  [CFG Analyzer](docs/guide/cfg-analyzer.md). New example:
  `examples/destructor_transition_example.nim`.

### Fixed

- **CFG analyzer recognizes method-call (dot-call) shapes.** The
  analyzer now treats the receiver `call[0][0]` of an
  `nnkCall`/`nnkCommand` with an `nnkDotExpr` head as the implicit first
  argument (parameter position 0) of the underlying proc. Pre-fix the
  per-call iteration walked only `call[1..N-1]`, missing the receiver
  entirely and false-firing CFG-001 on idiomatic `f.close()` /
  `f.transition()` / chained dot-call patterns. Prefix-call shape
  (`close(f)`) was unaffected and remains the same code path.
- **CFG analyzer pre-populates `var T` typestate-bearing params.** At
  proc entry the analyzer now seeds `LiveState` with one local per
  `var T` typestate-bearing formal parameter, captured at registration
  time into the new `RegisteredProc.typestatedParams` field. Pre-fix the
  live-set was empty at proc entry, so a proc that took
  `var f: File[Open]` and returned early without consuming `f` silently
  passed analysis. Sink-typed and value-typed params are NOT
  pre-populated: their values die with the proc frame regardless of
  whether the body textually references them (the proc's signature
  itself encodes the transition Src -> Dst). The analyzer also now
  recognizes the canonical conversion-consume idiom `Dst(src.Base)`,
  dropping a tracked local from the live-set when it appears inside a
  type-conversion call whose callee is a registered state-type ident.
- **CFG analyzer scoped to caller's module.** `verifyTypestates()` is
  now a template that captures the caller's absolute module path via
  `instantiationInfo(-1, fullPaths = true)` and forwards it to
  `verifyTypestatesImpl`. The implementation macro filters
  `registeredProcs` to entries whose `modulePath` matches the caller,
  applying that filter to the strictTransitions/external-proc check,
  the F5 decoy emission, and `runCfgAnalyzer`. Pre-fix every module's
  `verifyTypestates()` call re-walked every accumulated proc body from
  every imported module — O(N^2) compile-time cost across a project.
  Cross-module call-graph analysis remains a future enhancement;
  v0.9.0 analyzes the caller's module only. Legacy callers (e.g.
  CLI tooling) that invoke `runCfgAnalyzer()` directly with an empty
  `callerModulePath` continue to walk every registered proc.
- Declare `chronos` and `results` as test-only dependencies via
  `taskRequires "test", ...` in `typestates.nimble`. Previously, tests in
  `tests/should_compile/transitions/async_*` and
  `tests/should_compile/transitions/wrapper_result_*` failed to compile
  because their `chronos` / `results` imports were not resolved on a fresh
  `nimble test`. Production installs unaffected.

### Internal

- New `pkDestructorTransition` value on the `ProcKind` enum; new fields
  on `RegisteredProc`: `body*: NimNode`, `skipCfg*: bool`,
  `attachedObjectTypeName*: Option[string]`,
  `typestatedParams*: seq[TypestatedParam]`. New public type
  `TypestatedParam*` (name + stateType + graphName) captures
  typestate-bearing `var T` formal parameters at registration time so
  the CFG analyzer can pre-populate the live-set at proc entry.
- `verifyTypestates*` is now a template that captures the caller's
  module path via `instantiationInfo(-1, fullPaths = true)` and forwards
  it to a new `verifyTypestatesImpl*(callerFile: static[string])` macro,
  which scopes its per-proc scans to the caller's module. `runCfgAnalyzer*`
  gains an optional `callerModulePath` parameter (defaults to empty,
  preserving the all-procs behavior for direct callers).
- `destructorTransitionCore` shared implementation for both arities of
  `destructorTransition` (`src/typestates/pragmas.nim`).
- CFG analyzer pass integrated into `verifyTypestates*`
  (`src/typestates/verify.nim`), running after the unmarked-proc check
  and the F5 decoy pass.
- `generateAttachmentMarker` codegen helper emits a guarded
  per-typestate attachment macro plus the same-name fallback warning.
- Drop the unreachable sentinel `""` from `buildSingleTargetMatchCase`'s
  state-name `case` expression. `error` from `std/macros` aborts compilation,
  so the case type-checks as `string` from the three matching branches alone;
  the sentinel only added an `UnreachableCode` compiler warning visible
  during `nimble test`.
- Tighten `.gitignore` rule for nested test binaries. The prior pattern
  `tests/**/[a-z_]*/` (directory-level) excluded category subdirs like
  `tests/should_compile/transitions/`, which prevented re-including new
  `.nim` sources via `!tests/**/*.nim` (git forbids re-including files
  under an ignored parent). New file-level patterns target binaries one
  level below `should_*` without matching the category dirs themselves,
  so new test sources can be added without `git add -f`.

## [0.8.0] - 2026-05-07

### Added

- **Generated `match` macro per single-target state.** Every state in a
  typestate graph now emits a `match` macro overload alongside the
  existing per-branching-union overloads (introduced in v0.5.0). Callers
  can use identical `StateName(bind):` syntax whether the matched value
  is a branching union (e.g. `ProcessResult`) or a bare single-target
  state (e.g. `Approved` returned by `proc approve(c: sink Created): Approved {.transition.}`).
  The single-target `match` rewrites `match v: State(b): body` into
  `block: var valTmp = v; let b = move(valTmp); body` (call-expression
  value sources) or `block: let b = move(v); body` (l-value identifier
  sources), so the source expression is evaluated exactly once. The
  generated macros are disambiguated by Nim on the typed first
  parameter, so single-target and branching `match` coexist for the
  same state name when that state is reachable both as a branching arm
  (e.g. via `as Decision`) and as a bare return.

### Changed

- **BREAKING (DSL-level only):** Branch wrapper type names declared via
  `as TypeName` may no longer collide with any state name in the same
  typestate. Previously such a collision was syntactically accepted but
  would produce duplicate `type` definitions; with the new single-target
  `match` codegen it would also produce two `match*(value: <Name>; ...)`
  overloads with the same first-param type. The parser now errors
  before codegen with a message naming the offending wrapper and
  suggesting a distinct name (e.g., `ApprovedResult`). No existing
  in-tree typestate tripped this validation; downstream users with a
  collision must rename the wrapper.

### Internal

- New helper `buildSingleTargetMatchCase*(value, arms, validStateName)`
  in `src/typestates/codegen.nim`, paralleling `buildMatchCase`. Wraps
  the rewritten arm in a `block:` so adjacent matches that bind the
  same name do not collide, and uses a gensym'd `var valTmp` temporary
  for call-expression sources to satisfy `system.move`'s `var T`
  requirement while ensuring exactly-once evaluation.
- New generator `generateSingleTargetMatch*(graph)` emits one `match`
  macro per state in `graph.states`. Wired into `generateAll` after
  `generateBranchMatch`.
- New post-parse validator `validateNoBranchTypeStateCollision` in
  `src/typestates/parser.nim`, called from `parseTypestateBody`
  alongside the existing post-parse validators.
- Ten new test files under `tests/should_compile/transitions/` (six)
  and `tests/should_fail/transitions/` (four) cover: basic match,
  generic-context match, empty-object state, call-expr value source
  with side-effect-count assertion, two adjacent matches binding the
  same name, a state used in both branching and single-target paths,
  wrong-state arm, multi-arm, zero-arm, and the wrapper/state
  collision parser error.

## [0.7.2] - 2026-05-04

### Fixed

- `match` macro now expands correctly when invoked from a generic proc body whose call site does not directly import the kind enum module. The generated macro previously emitted bare `ident(prefix & stateName)` nodes for the `case` arms (e.g. `oOk`, `pApproved`); those idents had to resolve at the consumer's call site, which failed with `Error: undeclared identifier: '<field>'` when the consumer reached the typestate only through a facade that did not re-export the kind enum. The macro now pre-resolves each kind-enum field via `bindSym` at typestate-decl time (where the enum is in scope) and threads the resolved syms into `buildMatchCase`, so consumer-site visibility is no longer required.

### Internal

- `buildMatchCase` signature changed from `(value, arms, prefix: string, validNames: seq[string])` to `(value, arms, validNames: seq[string], kindSyms: seq[NimNode])`. The proc is documented internal-only and called solely from generated `match` macros, so no public API contract is broken.
- New regression test `tests/should_compile/transitions/match_external_consumer.nim` plus fixtures `tests/fixtures/match_consumer_lib.nim` and `tests/fixtures/match_consumer_wrapper.nim` exercise the three-module facade pattern: typestate-defining module, wrapper that imports but does not re-export it, and consumer that only sees the wrapper.

## [0.7.1] - 2026-05-02

### Fixed

- `match` macro now works in generic call sites (`proc[T]` / `template[T]` bodies). Previously, sema converted the arm-head identifier to `nnkSym` or `nnkOpenSymChoice` before the macro expanded, and `buildMatchCase` rejected those node kinds with "match arm head must be a single state identifier". The check now accepts `nnkIdent`, `nnkSym`, `nnkOpenSymChoice`, and `nnkClosedSymChoice` arm heads.

### Documentation

- `docs/guide/cli.md` now documents the v0.7 verify flags (`--warnings-as-errors` / `-W`, `--format=<default|github|json>`), describes the parse-error fail-soft behavior, and points to `ci-integration.md` for full coverage instead of duplicating CI examples.
- `docs/guide/verification.md` mentions the v0.7 flags with cross-links to `cli.md` and `ci-integration.md`.
- `docs/guide/ci-integration.md` adds a note on the parse-error fail-soft behavior (one bad file no longer aborts the rest of the batch).

## [0.7.0] - 2026-05-02

### Added

- New `--warnings-as-errors` flag (short alias `-W`) on `typestates verify`: promotes any warning to a non-zero exit, gating CI on lint warnings.
- New `--format=<default|github|json>` flag on `typestates verify`:
  - `github`: emits GitHub Actions annotation format (`::warning file=PATH,line=N::MESSAGE`) for inline PR review comments.
  - `json`: emits a documented stable schema with `schemaVersion: 1` envelope. See [CI Integration](docs/guide/ci-integration.md) for the schema spec.
- New `.pre-commit-hooks.yaml` hook manifest at repo root. Other repos can consume it by referencing `repo: https://github.com/elijahr/nim-typestates` in their `.pre-commit-config.yaml`.
- New documentation: [CI Integration](docs/guide/ci-integration.md) covers pre-commit, GitHub Actions, GitLab CI, treating warnings as errors, inline annotations, and the JSON schema.
- New stable code taxonomy for findings: `file-not-found`, `parse-error`, `unmarked-proc-strict`, `unmarked-proc`, `unreachable-state`, `non-terminal-state`, `orphan-state`, `no-entry-point`, `opaque-state-bypass`, `opaque-states-no-initials`. Codes are stable within a major version; documented stability policy in [CI Integration](docs/guide/ci-integration.md).
- `Finding.column: int` field captures column numbers from parser diagnostics. Surfaced as `column` in JSON output and as `col=N` in GitHub annotations when non-zero.

### Changed

- **BREAKING:** `VerifyResult.errors` and `VerifyResult.warnings` are now `seq[Finding]` instead of `seq[string]`. The new `Finding` record carries `path`, `line`, `severity`, `code`, `message`, and `hint` fields. Tests asserting on warning/error substrings should match against `it.message` (or `it.hint` for diagnostic hints from reachability findings). See [CI Integration](docs/guide/ci-integration.md) for the full schema.
- Reachability warnings (rfDead, rfTrap, rfOrphan, rfNoEntryPoint) now split message and hint into separate fields. The default human-readable output is unchanged from v0.6.
- ParseError on input files now routes through the Finding pipeline as a `parse-error` code. Under `--format=github` and `--format=json`, parse failures produce annotation/JSON output rather than plain stderr text. A parse error in one file no longer aborts verification of the rest of the batch — every problem surfaces in a single run.

### Internal

- New module `src/typestates/findings.nim` containing `Finding`, `Severity`, `FindingCode`, helpers (`mkError`, `mkWarning`), and formatters (`formatHuman`, `formatGitHub`, `formatJson`).
- All warning/error emission sites in `cli.nim`, `reachability.nim`, and `lint_opaque_states.nim` migrated to construct `Finding` records.
- `.gitignore` whitelists `tests/fixtures/**` and common non-Nim file types under `src/typestates/`. Preventive against future fixture additions being silently ignored.
- New tests: `tcli_verify_formats.nim`, `tcli_warnings_as_errors.nim`, `tcli_parse_error.nim`, `tcli_gitignore.nim`. Existing tests `tcli.nim`, `tcli_verify_warnings.nim`, `tcli_opaque_states.nim`, `tlint_opaque_states.nim` migrated to the Finding API.

## [0.6.0] - 2026-04-30

### Added

- `opaqueStates = true` opt-in flag for typestate declarations. Enables a CLI-side lint that emits warnings when raw distinct casts construct non-initial states outside `{.transition.}` procs. See [Cast Protection guide](docs/guide/cast-protection.md) for caught/missed surface and known limitations. Warnings only; no compile-time enforcement.

### Internal

- New module `src/typestates/lint_opaque_states.nim`.
- New public proc `parsePNode` in `ast_parser` (extracted from `parseFileWithAst` to share parser-init code with the lint).

## [0.5.0] - 2026-05-01

### Added

- **Auto-generated `$` overload for typestate values.** Each leaf state type
  and the generated state enum now have a `$` proc returning the bare state
  name (no `fs` prefix). Under the default `consumeOnTransition = true`, calling
  `$` on a value will consume it; the docs call out this interaction and the
  workaround (`$state(value)`).
- **Reachability and liveness warnings.** New `initial:` and `terminal:` DSL
  blocks let the parser flag unreachable states and dead-end (non-terminal)
  states at compile time. The `typestates verify` CLI surfaces the same
  warnings on `.nim` files without rebuilding.
- **Generated `match` macro per branching union.** Every `as TypeName` branch
  type now emits a `match` macro that dispatches on the variant kind with
  compile-time exhaustiveness checking. The matched value must be `var`
  (branch fields are extracted with `move`), arms use `StateName(bind):`
  syntax, and missing or unknown branches error at the call site.
- **State-aware error messages on transition misuse.** When a module calls
  `verifyTypestates()`, every non-generic, non-branching `{.transition.}` proc
  now also emits `{.error.}` decoy overloads for the other states in its
  typestate, with consistent extra parameters across overloads (an
  `anySkipped`-style flag keeps the decoy and live signatures shaped
  identically). Calling a transition with the wrong source state surfaces a
  tailored message naming the proc, the wrong state, and the expected source,
  instead of Nim's generic "type mismatch" diagnostic. Generic typestates and
  branching-return procs are skipped in v0.5 and tracked as a v0.6 follow-up.

### Fixed

- **README payment example compiles under default `consumeOnTransition`.**
  Transition procs in the README now take `sink` parameters, the async
  section was corrected, and a regression fixture covers the example.

## [0.4.1] - 2026-04-30

### Fixed

- **CLI `--version` reported the wrong version.** `typestates --version`
  printed `typestates 0.3.0` regardless of the installed package version
  because the string was hardcoded in `showVersion()`. The CLI now derives
  the version from `NimblePkgVersion` at build time, keeping the package
  version (`typestates.nimble`) as the single source of truth. The
  `buildCli` task forwards the version through `-d:NimblePkgVersion=` so
  developer builds match `nimble install` output.

### Documentation

- README rewritten for clarity. Tightened prose, replaced the Key Features
  table with a flat list, added a Cross-Type Bridges example, surfaced the
  Nim < 2.2.8 codegen workaround inline, and trimmed the documentation
  link list to point readers at the docs site for the long tail.

## [0.4.0] - 2026-04-23

### Added

- **Transparent-wrapper unwrapping for transition return types.**
  `{.transition.}` now looks through transparent wrappers (built-in:
  `Result`, `Option`, `Future`) to find the destination state. Procs
  like `proc f(s: A): Result[B, E] {.transition.}` and
  `proc g(s: A): Option[B] {.transition.}` validate the underlying
  A → B edge transparently.
- **Async/Future return-type validation.** `{.async, transition.}`
  procs returning `Future[T]`, `Future[Result[T, E]]`, or any
  combination of registered transparent wrappers now validate the
  underlying destination state. Pragma order is interchangeable;
  `{.transition, async.}` is recommended for forward-compat with
  future body-level analysis.
- New public API for transparent-wrapper management:
    - `{.transparentWrapper.}` marker pragma (cosmetic; the wrapped
      state type must be the wrapper's first generic argument)
    - `registerTransparentWrapper(name: string)` — register a wrapper
      type (base or module-qualified name) at `static:` time
    - `unregisterTransparentWrapper(name: string)` — opt out of a
      built-in or previously-registered wrapper
    - `isTransparentWrapper(name: string): bool` — predicate
- Test runner extension: `tests/tcomprehensive_runner.nim` now
  supports `# expects: "<substring>"` directives in `should_fail/`
  test files. The runner AND-checks each substring against captured
  compiler output. Backward-compatible (existing tests unaffected).
- Direct test coverage for the Nim issue #25341 codegen-bug gate:
    - `tests/should_fail/consume/codegen_bug_gate.nim` exercises
      the live gate on Nim < 2.2.8 and emits an equivalent diagnostic
      on Nim >= 2.2.8 to remain green on both.
    - `tests/should_compile/consume/codegen_bug_clean.nim` proves
      the gated typestate shape compiles cleanly on Nim >= 2.2.8.
  Together these tests verify the version triple gate is empirically
  correct against the upstream multi-file repro on both Nim 2.2.6
  (gate must fire) and Nim 2.2.8 (gate must be silent).

### Fixed

- **Union source parameters on transition procs.** `{.transition.}`
  now accepts union source parameters like `Open | PartiallyFilled`.
  Per-source diagnostics name the specific failing source state.
  Implemented via a new `extractAllSourceTypeNames` proc that mirrors
  the existing return-side union-type recursion.
- `extractAllSourceTypeNames` strips parameter modifiers
  (`sink`, `var`, `ref`, `ptr`) and explicit parentheses
  (`nnkPar` / `nnkTupleConstr`) before splitting on the union operator,
  so `sink (A | B)`, `var (A | B)`, and `(A | B)` all behave like
  `A | B` instead of falling through to the leaf fallback as a single
  opaque string.
- `extractAllTypeNames` peels single-element parenthesis wrappers ahead
  of the union case, so a parenthesized union inside a transparent
  wrapper (e.g., `Result[(A | B), E]`) matches each branch against the
  transition graph rather than the literal `"(A | B)"`.
- `extractAllTypeNames` also peels `ref` / `ptr` / `var` / `sink`
  modifiers on return types, so `proc f(a: A): ref B` validates
  `A -> B` instead of reporting "Undeclared transition: A -> ref B".
- `extractTypeName` on an `nnkBracketExpr` no longer crashes on a
  module-qualified head (`mymod.State[T]`). The head is delegated back
  to `extractTypeName`, which routes `DotExpr` through `node.repr`
  instead of a missing `.strVal`.
- The source-type extractor uses `nnkIdentDefs[^2]` instead of `[1]`,
  so transitions with grouped parameter idents (e.g.,
  `proc m(a, b: State)`) correctly identify the type node rather than
  reporting a confusing "<second-ident-name> is not part of any
  registered typestate" error.
- The single-source fallback in `extractAllSourceTypeNames` now uses
  the stripped node, so a lone parenthesized source like `(A)`
  resolves to `A` and matches the graph.
- `unwrapTransparent` bails out when an `nnkBracketExpr` has fewer than
  two children, avoiding an out-of-bounds access on macro-generated or
  malformed empty-arg wrappers.

### Behavior notes

- Users with a project-local generic type named `Result` used as a
  typestate state (rather than an error wrapper) should call
  `static: unregisterTransparentWrapper("Result")` near the typestate
  declaration to opt out of the built-in unwrap.
- Combining `{.async, transition.}` with `consumeOnTransition = true`
  may hit a chronos `Future.complete` by-value issue (chronos
  limitation, not nim-typestates). Mitigation: set
  `consumeOnTransition = false` for the affected typestate, or use
  `sink` parameter modifier explicitly.
- Recommended pragma order is `{.transition, async.}` (both orderings
  work for signature validation; transition-first is forward-compat
  with future body-level analysis).
- Registered transparent wrappers must put the wrapped state type at
  the first generic-argument position (`Wrapper[State, ...]`). This
  matches the built-in seeds (`Result[T, E]`, `Option[T]`, `Future[T]`).
  Wrappers that put the state elsewhere should NOT be registered.

### Known limitations

- Wrapper-name registry uses string-based matching against bare or
  module-qualified names. A user defining their own `Result` type in
  a project would silently get unwrapped. Use
  `unregisterTransparentWrapper("Result")` to opt out, or a different
  name that doesn't collide with the built-in seeds.

### Tooling

- Pre-commit hook configured for `nph` formatting; CI now runs a
  dedicated lint job alongside the test matrix.
- CI test matrix pinned to Nim `2.2.0` (minimum supported) and `2.2.8`
  (boundary version with the Nim issue #25341 fix). Avoids silent
  drift from `stable`.
- Replaced the broken `asdf-vm/actions/setup` chain with
  `jiro4989/setup-nim-action@v2`; added explicit installation of
  `results` and `chronos` test dependencies.
- `mkdocstrings-nim` updated to v0.2.1.

### Documentation

- New guide page: [Transparent Wrappers](docs/guide/transparent-wrappers.md)
  covers `Result` / `Option` / `Future` return-type unwrapping, custom
  wrapper registration, the first-generic-argument contract, and the
  opt-out path.
- DSL reference documents union source parameters and links to the
  transparent-wrappers page under `{.transition.}`.
- Error-handling guide documents direct `Result[State, E]` and
  `Future[Result[State, E]]` returns as alternatives to branch types.
- README and landing page list the new features.

## [0.3.1] - 2025-12-12

### Fixed

- CLI parser now correctly handles generic typestates (e.g., `EpochGuardContext[MaxThreads]`)
  - Added `nkBracketExpr` handling in AST parser for generic state names
  - Generic states now appear correctly in DOT visualization output
- DOT output now quotes identifiers containing brackets or other special characters
  - Fixes Graphviz syntax errors with generic states like `Unpinned[MaxThreads]`

## [0.3.0] - 2025-12-12

### Added

- `codegen` CLI command to output generated helper code
  - Shows the state enum, union type, state procs, and branch types
  - Useful for understanding what the macro generates
  - Usage: `typestates codegen src/myfile.nim`
- Module-qualified bridge syntax (`module.Typestate.State`) for cross-module bridges
  - Enables explicit documentation of which module a bridge target comes from
  - Module qualifiers are metadata for documentation and visualization
  - Validation uses base names for flexibility
- Automatic constraint inference for generic typestates
  - Unconstrained generic parameters (e.g., `[N]`) are automatically inferred from state type definitions
  - Reduces boilerplate when state types already declare constraints
- Library Modularity guide documenting typestate composition patterns
  - Shows how libraries can expose typestates for external consumption
  - Uses nim-debra as a case study
- Comprehensive test coverage for module-qualified bridges
  - Generic typestates with module-qualified bridges
  - Branching transitions with module-qualified bridges
  - Visualization output verification

### Fixed

- DOT generation now properly quotes bridge destinations containing dots
  - Fixes Graphviz syntax errors with module-qualified names like `module.Type.State`
- DOT unified graph now uses `fullDestRepr` for complete bridge destination names
- Improved error messages for codegen bug detection

### Documentation

- Added module-qualified syntax to bridges guide and DSL reference
- Added all guide sections to README documentation links

## [0.2.1] - 2025-12-07

### Added

- Compile-time detection of Nim codegen bug ([nim-lang/Nim#25341](https://github.com/nim-lang/Nim/issues/25341))
  - Affects `static` generic parameters with ARC/ORC/AtomicARC on Nim < 2.2.8
  - Shows clear error message with four workaround options
  - Regular generics (`Container[T]`) are not affected
- `inheritsFromRootObj` flag to suppress the static generic check when using `RootObj` workaround
- `consumeOnTransition` flag (default: `true`)
  - State types cannot be copied, preventing accidental reuse of stale states
  - Opt out with `consumeOnTransition = false`
- `initial:` and `terminal:` state declarations
  - Initial states can only be constructed, not transitioned to
  - Terminal states cannot transition to anything else
  - Validated at both DSL and transition pragma level
- Multiline state list syntax with optional newlines
  ```nim
  states:
    Closed
    Open
    Errored
  ```
- Parenthesized syntax for branching transitions: `A -> (B | C) as Result`

### Changed

- Minimum Nim version bumped to 2.2.0
- States must have unique base type names
  - Using same type with different static params (e.g., `GPIO[false]` vs `GPIO[true]`) now shows clear error
  - Documentation explains wrapper type pattern as workaround

### Documentation

- Added warning banner about Nim < 2.2.8 static generics bug to README, docs index, and getting started guide
- Added Flags section to DSL reference documenting `strictTransitions`, `consumeOnTransition`, and `inheritsFromRootObj`

## [0.2.0] - 2025-12-06

### Added

- Full helper code generation for generic typestates (`Container[T]`, `Map[K, V]`)
  - State enum (e.g., `ContainerState`)
  - Union type with generics (e.g., `ContainerStates[T]`)
  - Generic state procs (e.g., `proc state[T](c: Empty[T]): ContainerState`)
  - Generic branch types (e.g., `FillResult[T]`)
  - Generic branch constructors (e.g., `toFillResult[T]`)
  - Generic branch operators (e.g., `FillResult[T] -> Full[T](...)`)
- Support for constrained generic parameters (`N: static int`, `T: SomeNumber`, etc.)
- Cross-type state bridges (`bridges:` block for transitioning between typestates)
- `>>>` operator for branch type construction (deprecated in favor of `->`)
- Explicit `as TypeName` syntax required for branching transitions
- Comprehensive test suite with should-compile and should-fail test categories
- Styled DOT output with deep purple theme matching mkdocs-material
  - Rounded boxes with purple borders (#673ab7)
  - Transparent background for web embedding
  - Differentiated edge styles: solid (normal), dotted gray (wildcard), dashed purple (bridges)
- CLI visualization options
  - `--splines=MODE` for edge routing: `spline` (curved, default), `ortho` (right-angle), `polyline`, `line`
  - `--separate` to generate one graph per typestate
  - `--no-style` for minimal DOT output without styling
- Smart edge distribution using compass points for cleaner diagrams
- Dark mode styling for diagrams matching mkdocs-material slate theme
- Auto-generated diagram infrastructure
  - `examples/snippets/` directory for diagram source files
  - `scripts/generate_diagrams.py` for batch SVG generation
- CI compilation tests for all example files
- `mkdocs-include-markdown-plugin` for embedding code snippets
- Contributing guide

### Changed

- Documentation updated with accurate code samples matching actual library behavior
- Visualization guide updated with new styled DOT format and edge style reference
- Improved node spacing and margins for better readability
- Use Inter font stack for consistent typography

### Fixed

- Validate bridge destination states exist in target typestate
- Validate no duplicate branching transitions from same source state
- Generic branch type lookup now correctly matches types with constraints (e.g., `EmptyCheck[N]`)
- All example files now compile (added missing `as TypeName` on branching transitions)
- Pin `click<8.3.0` to fix mkdocs serve file watching
- Removed auto-regeneration hook that caused infinite rebuild loops

## [0.1.0] - 2025-12-03

### Added

- `typestate` macro for declaring states and transitions
- `{.transition.}` pragma with compile-time validation
- `{.notATransition.}` pragma for non-transitioning operations
- Branching transitions (`A -> B | C`)
- Wildcard transitions (`* -> A`)
- Generic typestate support (`typestate Container[T]`)
- Strict mode with `strictTransitions` flag
- Sealed typestates with `isSealed` flag
- Generated helper types (`FileState` enum, `FileStates` union)
- `{.raises: [].}` enforcement on transitions
- CLI tool (`typestates`) for verification and DOT graph generation

[Unreleased]: https://github.com/elijahr/nim-typestates/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/elijahr/nim-typestates/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/elijahr/nim-typestates/compare/v0.7.2...v0.8.0
[0.7.2]: https://github.com/elijahr/nim-typestates/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/elijahr/nim-typestates/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/elijahr/nim-typestates/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/elijahr/nim-typestates/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/elijahr/nim-typestates/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/elijahr/nim-typestates/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/elijahr/nim-typestates/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/elijahr/nim-typestates/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/elijahr/nim-typestates/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/elijahr/nim-typestates/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/elijahr/nim-typestates/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/elijahr/nim-typestates/releases/tag/v0.1.0
