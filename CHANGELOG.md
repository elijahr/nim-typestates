# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Full helper code generation for generic typestates (`Container[T]`, `Map[K, V]`)
  - State enum (e.g., `ContainerState`)
  - Union type with generics (e.g., `ContainerStates[T]`)
  - Generic state procs (e.g., `proc state[T](c: Empty[T]): ContainerState`)
  - Generic branch types (e.g., `FillResult[T]`)
  - Generic branch constructors (e.g., `toFillResult[T]`)
  - Generic branch operators (e.g., `FillResult[T] -> Full[T](...)`)
- Cross-type state bridges (`bridges:` block for transitioning between typestates)
- `>>>` operator for branch type construction (deprecated in favor of `->`)
- Explicit `as TypeName` syntax required for branching transitions
- Comprehensive test suite with should-compile and should-fail test categories

### Fixed

- Validate bridge destination states exist in target typestate
- Validate no duplicate branching transitions from same source state

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

[Unreleased]: https://github.com/elijahr/nim-typestates/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/elijahr/nim-typestates/releases/tag/v0.1.0
