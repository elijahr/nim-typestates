# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[Unreleased]: https://github.com/elijahr/nim-typestates/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/elijahr/nim-typestates/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/elijahr/nim-typestates/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/elijahr/nim-typestates/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/elijahr/nim-typestates/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/elijahr/nim-typestates/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/elijahr/nim-typestates/releases/tag/v0.1.0
