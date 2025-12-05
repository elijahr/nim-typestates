# Contributing

Guidelines for contributing to nim-typestates.

## Development Setup

```bash
# Clone the repository
git clone https://github.com/elijahr/nim-typestates.git
cd nim-typestates

# Install dependencies
nimble install -d

# Build the CLI
nimble build

# Run tests
nimble test
```

## Running Tests

```bash
# Run all tests
nimble test

# Run specific test file
nim c -r tests/tbasic.nim
```

## Documentation

### Local Preview

```bash
# Install Python dependencies
pip install -r docs-requirements.txt

# Serve docs locally
mkdocs serve
```

### Auto-Generated Diagrams

The diagrams in this documentation are automatically generated from source code snippets. This ensures they stay in sync with the actual typestate definitions.

#### Generating Diagrams

```bash
# Generate all diagrams from examples/snippets/
nimble generateDocs

# Or manually:
python3 scripts/generate_diagrams.py
```

This reads `*_typestate.nim` files from `examples/snippets/` and generates SVG diagrams in `docs/assets/images/generated/`.

#### Creating New Diagram Sources

To add a new auto-generated diagram:

1. Create a snippet in `examples/snippets/yourname_typestate.nim`:

```nim
import ../../src/typestates

type
  YourType = object
  StateA = distinct YourType
  StateB = distinct YourType

typestate YourType:
  states StateA, StateB
  transitions:
    StateA -> StateB
```

2. Run `nimble generateDocs` to regenerate all diagrams.

3. Reference the generated image in docs: `![YourType](assets/images/generated/yourtype.svg)`

## Code Style

- Follow standard Nim style conventions
- Use `nimble format` if available
- Keep lines under 100 characters where practical

## Pull Requests

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `nimble test`
5. Submit a pull request

## Reporting Issues

Please include:

- Nim version (`nim --version`)
- nim-typestates version
- Minimal reproduction case
- Expected vs actual behavior
