# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/elijahr/nim-typestates/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/elijahr/nim-typestates/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/elijahr/nim-typestates/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/elijahr/nim-typestates/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/elijahr/nim-typestates/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/elijahr/nim-typestates/releases/tag/v0.1.0
