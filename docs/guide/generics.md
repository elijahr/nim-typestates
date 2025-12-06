# Generic Typestates

nim-typestates supports generic type parameters, enabling reusable typestate patterns.

## Basic Generic Typestate

Define a typestate with type parameters:

```nim
import typestates

type
  Container[T] = object
    value: T
  Empty[T] = distinct Container[T]
  Full[T] = distinct Container[T]

typestate Container[T]:
  states Empty[T], Full[T]
  transitions:
    Empty[T] -> Full[T]
    Full[T] -> Empty[T]
```

Implement transitions using generic procs:

```nim
proc fill[T](c: Empty[T], val: T): Full[T] {.transition.} =
  var cont = Container[T](c)
  cont.value = val
  result = Full[T](cont)

proc empty[T](c: Full[T]): Empty[T] {.transition.} =
  result = Empty[T](Container[T](c))
```

Use with any type:

```nim
# With int
let e = Empty[int](Container[int](value: 0))
let f = e.fill(42)
let e2 = f.empty()

# With string
let s = Empty[string](Container[string](value: ""))
let s2 = s.fill("hello")
```

## Multiple Type Parameters

Typestates can have multiple type parameters:

```nim
type
  KeyValue[K, V] = object
    key: K
    value: V
  EmptyKV[K, V] = distinct KeyValue[K, V]
  HasKey[K, V] = distinct KeyValue[K, V]
  HasBoth[K, V] = distinct KeyValue[K, V]

typestate KeyValue[K, V]:
  states EmptyKV[K, V], HasKey[K, V], HasBoth[K, V]
  transitions:
    EmptyKV[K, V] -> HasKey[K, V]
    HasKey[K, V] -> HasBoth[K, V]
    HasBoth[K, V] -> EmptyKV[K, V]

proc setKey[K, V](kv: EmptyKV[K, V], key: K): HasKey[K, V] {.transition.} =
  var obj = KeyValue[K, V](kv)
  obj.key = key
  result = HasKey[K, V](obj)

proc setValue[K, V](kv: HasKey[K, V], value: V): HasBoth[K, V] {.transition.} =
  var obj = KeyValue[K, V](kv)
  obj.value = value
  result = HasBoth[K, V](obj)
```

## Non-Transitions with Generics

Use `{.notATransition.}` for operations that don't change state:

```nim
proc peek[T](c: Full[T]): T {.notATransition.} =
  Container[T](c).value

proc size[K, V](kv: HasBoth[K, V]): int {.notATransition.} =
  1  # Always contains one key-value pair
```

## Type Conversion Syntax

When converting between distinct generic types, use `Type[params](value)` syntax:

```nim
# Correct - explicit generic parameters
var cont = Container[T](c)        # From distinct to base
result = Full[T](cont)            # From base to distinct

# Wrong - method call syntax doesn't work with generics
# var cont = c.Container[T]       # Compile error
```

## Generated Helpers

Generic typestates get fully parameterized helper types:

| Helper | Non-Generic Example | Generic Example |
|--------|---------------------|-----------------|
| State enum | `FileState = enum fsClosed, fsOpen` | `ContainerState = enum fsEmpty, fsFull` |
| Union type | `FileStates = Closed \| Open` | `ContainerStates[T] = Empty[T] \| Full[T]` |
| State procs | `proc state(f: Closed): FileState` | `proc state[T](c: Empty[T]): ContainerState` |

Usage example:

```nim
# State enum works the same
check fsEmpty is ContainerState
check fsFull is ContainerState

# Union type is parameterized
proc acceptAny[T](c: ContainerStates[T]): ContainerState =
  c.state

let e = Empty[int](Container[int](value: 0))
check acceptAny(e) == fsEmpty

# State procs are generic
let f = Full[string](Container[string](value: "hello"))
check f.state == fsFull
```

## Branching Transitions with Generics

Generic typestates fully support branching transitions with parameterized branch types:

```nim
type
  Container[T] = object
    value: T
  Empty[T] = distinct Container[T]
  Full[T] = distinct Container[T]
  Error[T] = distinct Container[T]

typestate Container[T]:
  states Empty[T], Full[T], Error[T]
  transitions:
    Empty[T] -> Full[T] | Error[T] as FillResult[T]
    Full[T] -> Empty[T]
```

This generates:

```nim
# Branch type enum (not parameterized)
type FillResultKind* = enum fFull, fError

# Branch type (parameterized)
type FillResult*[T] = object
  case kind*: FillResultKind
  of fFull: full*: Full[T]
  of fError: error*: Error[T]

# Constructors (generic)
proc toFillResult*[T](s: Full[T]): FillResult[T]
proc toFillResult*[T](s: Error[T]): FillResult[T]

# Operator (generic)
template `->`*[T](_: typedesc[FillResult[T]], s: Full[T]): FillResult[T]
template `->`*[T](_: typedesc[FillResult[T]], s: Error[T]): FillResult[T]
```

Usage:

```nim
proc fill[T](e: Empty[T], val: T): FillResult[T] =
  if val == default(T):
    FillResult[T] -> Error[T](Container[T](e))
  else:
    var c = Container[T](e)
    c.value = val
    FillResult[T] -> Full[T](c)

let empty = Empty[int](Container[int](value: 0))
let result = fill(empty, 42)

case result.kind
of fFull: echo "Got value: ", Container[int](result.full).value
of fError: echo "Failed"
```

## Supported Type Expressions

Generic typestates support various type expressions:

| Type Expression | Example | Notes |
|-----------------|---------|-------|
| Simple generics | `Container[T]` | Single type parameter |
| Multi-param generics | `Map[K, V]` | Multiple type parameters |
| Nested generics | `Container[seq[T]]` | Generic of generic |
| Constrained generics | `Container[T: SomeInteger]` | With type bounds (see below) |
| Static parameters | `Buffer[N: static int]` | Compile-time values |

## Constrained Generic Parameters

When using constrained generic parameters, **you must repeat the constraint in the typestate declaration**. This applies to all constraints including type bounds (`SomeInteger`, `SomeNumber`) and static parameters (`static int`).

```nim
type
  # Type definitions with constraints
  Buffer[N: static int] = object
    data: array[N, byte]
  Empty[N: static int] = distinct Buffer[N]
  Full[N: static int] = distinct Buffer[N]

# Constraint MUST be repeated in typestate header
typestate Buffer[N: static int]:
  states Empty[N], Full[N]
  transitions:
    Empty[N] -> Full[N]
    Full[N] -> Empty[N]
```

The same applies to type constraints:

```nim
type
  NumericContainer[T: SomeNumber] = object
    value: T
  Unset[T: SomeNumber] = distinct NumericContainer[T]
  Set[T: SomeNumber] = distinct NumericContainer[T]

# Constraint MUST be repeated
typestate NumericContainer[T: SomeNumber]:
  states Unset[T], Set[T]
  transitions:
    Unset[T] -> Set[T]
```

## Pattern: Builder with Required Fields

Use generics to track which fields have been set:

```nim
type
  UserBuilder = object
    name: string
    email: string

  NeedsBoth = distinct UserBuilder
  NeedsEmail = distinct UserBuilder
  Complete = distinct UserBuilder

typestate UserBuilder:
  states NeedsBoth, NeedsEmail, Complete
  transitions:
    NeedsBoth -> NeedsEmail
    NeedsEmail -> Complete

proc withName(b: NeedsBoth, name: string): NeedsEmail {.transition.} =
  var builder = UserBuilder(b)
  builder.name = name
  result = NeedsEmail(builder)

proc withEmail(b: NeedsEmail, email: string): Complete {.transition.} =
  var builder = UserBuilder(b)
  builder.email = email
  result = Complete(builder)

proc build(b: Complete): User {.notATransition.} =
  let builder = UserBuilder(b)
  User(name: builder.name, email: builder.email)
```

## Pattern: Resource Wrapper

Wrap any resource type with acquire/release protocol:

```nim
type
  Resource[T] = object
    handle: T
  Released[T] = distinct Resource[T]
  Acquired[T] = distinct Resource[T]

typestate Resource[T]:
  states Released[T], Acquired[T]
  transitions:
    Released[T] -> Acquired[T]
    Acquired[T] -> Released[T]

proc acquire[T](r: Released[T], handle: T): Acquired[T] {.transition.} =
  var res = Resource[T](r)
  res.handle = handle
  result = Acquired[T](res)

proc release[T](r: Acquired[T]): Released[T] {.transition.} =
  result = Released[T](Resource[T](r))

proc use[T](r: Acquired[T]): T {.notATransition.} =
  Resource[T](r).handle
```

## Static Parameters as State Differentiation

A common pattern in embedded programming (see [Nim forum discussion](https://forum.nim-lang.org/t/9976)) uses static parameters to differentiate states at compile time:

```nim
# What you might want to write (DOES NOT WORK):
type
  GPIO[Enabled: static bool, Dir: static Option[Direction]] = object
    pin: int

typestate GPIO[Enabled: static bool, Dir: static Option[Direction]]:
  states GPIO[false, none(Direction)], GPIO[true, none(Direction)]
  transitions:
    GPIO[false, none(Direction)] -> GPIO[true, none(Direction)]
```

This fails because all states share the same base name `GPIO`. The library cannot generate unique enum values, union types, or state procs when base names collide.

**Use distinct wrapper types instead:**

```nim
type
  GPIO[Enabled: static bool, Dir: static Option[Direction]] = object
    pin: int

  # Wrapper types with unique base names
  Disabled = distinct GPIO[false, none(Direction)]
  EnabledNoDir = distinct GPIO[true, none(Direction)]
  InputMode = distinct GPIO[true, some(Input)]
  OutputMode = distinct GPIO[true, some(Output)]

typestate GPIO[Enabled: static bool, Dir: static Option[Direction]]:
  states Disabled, EnabledNoDir, InputMode, OutputMode
  transitions:
    Disabled -> EnabledNoDir
    EnabledNoDir -> InputMode
    EnabledNoDir -> OutputMode

proc enable(g: Disabled): EnabledNoDir {.transition.} =
  EnabledNoDir(GPIO[true, none(Direction)](pin: GPIO[false, none(Direction)](g).pin))

proc setInput(g: EnabledNoDir): InputMode {.transition.} =
  InputMode(GPIO[true, some(Input)](pin: GPIO[true, none(Direction)](g).pin))
```

This approach:

- Preserves the zero-cost abstraction (distinct types compile away)
- Gives states meaningful names in error messages
- Works with all library features (enums, unions, branching)

## Limitations

1. **Constraints must be repeated**: Generic constraints (`static int`, `SomeInteger`, etc.) must be explicitly stated in the typestate header - they cannot be inferred from type definitions. See [Constrained Generic Parameters](#constrained-generic-parameters).

2. **Unique base names required**: All states must have distinct base type names. Using the same type with different parameters (like `GPIO[false]` vs `GPIO[true]`) is not supported. See [Static Parameters as State Differentiation](#static-parameters-as-state-differentiation) for the workaround.

3. **Branch type params must match**: Branch type parameters must use the same type variables as the typestate (e.g., `FillResult[K]` when typestate uses `T` will fail).

4. **Distinct types with multiple params**: Due to a Nim compiler limitation, using `distinct` with multiple generic params may cause C compilation errors. Use wrapper objects instead:

```nim
# May cause issues with distinct
type EmptyMap[K, V] = distinct Map[K, V]

# Works reliably
type EmptyMap[K, V] = object
  inner: Map[K, V]
```

## Next Steps

- [DSL Reference](dsl-reference.md) - Complete syntax reference
- [Examples](examples.md) - More usage patterns
