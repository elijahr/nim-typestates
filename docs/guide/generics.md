# Generic Typestates

nim-typestates supports generic type parameters, enabling reusable typestate patterns.

## Basic Generic Typestate

Define a typestate with type parameters:

```nim
import nim_typestates

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

For generic typestates, helper types (enum, union, state procs) are **not generated** because the type parameters aren't in scope for the generated code. The core validation still works.

For non-generic typestates, these are generated:

| Helper | Example | Generated For Generics? |
|--------|---------|-------------------------|
| State enum | `ContainerState = enum fsEmpty, fsFull` | No |
| Union type | `ContainerStates = Empty | Full` | No |
| State procs | `proc state(c: Empty): ContainerState` | No |

You can create your own helpers if needed:

```nim
proc isEmptyState[T](c: Empty[T]): bool = true
proc isEmptyState[T](c: Full[T]): bool = false

proc isFull[T](c: Empty[T]): bool = false
proc isFull[T](c: Full[T]): bool = true
```

## Supported Type Expressions

Generic typestates support various type expressions:

| Type Expression | Example | Notes |
|-----------------|---------|-------|
| Simple generics | `Container[T]` | Single type parameter |
| Multi-param generics | `Map[K, V]` | Multiple type parameters |
| Nested generics | `Container[seq[T]]` | Generic of generic |
| Constrained generics | `Container[T: SomeInteger]` | With type bounds |

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

## Limitations

1. **No helper generation**: Generic typestates don't get enum/union/state proc helpers
2. **Same base name**: All states in a generic typestate must have distinct base names (e.g., `Empty[T]` and `Empty[V]` would conflict)

## Next Steps

- [DSL Reference](dsl-reference.md) - Complete syntax reference
- [Examples](examples.md) - More usage patterns
