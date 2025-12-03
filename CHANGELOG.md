# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
