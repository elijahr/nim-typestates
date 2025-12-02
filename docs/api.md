# API Reference

Auto-generated API documentation from source code.

## Main Module

::: typestates

---

## Module Overview

### `typestates`

The main module. Import this to use the library.

**Exports:**

- `typestate` macro - Declare states and transitions
- `transition` pragma - Mark and validate transition procs
- `notATransition` pragma - Mark non-transition procs

### `typestates/types`

Core type definitions (internal).

- `State` - Represents a single state
- `Transition` - Represents a valid transition
- `TypestateGraph` - Complete typestate definition

### `typestates/parser`

DSL parser (internal).

- `parseTypestateBody` - Parse typestate block into graph
- `parseStates` - Parse states declaration
- `parseTransition` - Parse single transition

### `typestates/registry`

Compile-time typestate storage (internal).

- `typestateRegistry` - Global registry
- `registerTypestate` - Add typestate to registry
- `findTypestateForState` - Look up typestate by state name

### `typestates/pragmas`

Pragma implementations.

- `transition` macro - Validates state transitions
- `notATransition` template - Marks non-transitions

### `typestates/codegen`

Code generation (internal).

- `generateStateEnum` - Generate `FileState` enum
- `generateUnionType` - Generate `FileStates` union
- `generateStateProcs` - Generate `state()` procs

### `typestates/cli`

Command-line tool functionality.

- `parseTypestates` - Parse typestate definitions from source files
- `generateDot` - Generate GraphViz DOT from parsed typestates
- `verify` - Verify typestate rules in source files

## Quick Reference

### Typestate Declaration

```nim
typestate TypeName:
  states State1, State2, State3
  transitions:
    State1 -> State2
    State2 -> State1 | State3
    * -> State1
```

### Transition Proc

```nim
proc doThing(s: State1): State2 {.transition.} =
  result = State2(s.TypeName)
```

### Non-Transition Proc

```nim
proc sideEffect(s: State1) {.notATransition.} =
  # Does something but doesn't change state
  discard
```

### Generated Types

For `typestate File:` with states `Closed`, `Open`:

```nim
# Enum
type FileState* = enum fsClosed, fsOpen

# Union
type FileStates* = Closed | Open

# Procs
proc state*(f: Closed): FileState
proc state*(f: Open): FileState
```
