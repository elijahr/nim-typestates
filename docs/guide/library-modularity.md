# Library Modularity

Typestates enable a powerful pattern: libraries can export typestate-enforced protocols that consumers plug into.

## The Pattern

1. **Library defines typestates** for its protocol (states, transitions)
2. **Consumer imports library** and uses those typestates directly
3. **Compiler enforces** correct protocol usage at the consumer's call sites
4. **Consumer's typestates** can bridge to/from library typestates

## Example: DEBRA Memory Reclamation

[nim-debra](https://github.com/elijahr/nim-debra) implements the DEBRA+ algorithm using typestates:

```nim
# In debra library:
typestate EpochGuardContext[MaxThreads: static int]:
  states Unpinned[MaxThreads], Pinned[MaxThreads], Neutralized[MaxThreads]
  transitions:
    Unpinned[MaxThreads] -> Pinned[MaxThreads]
    Pinned[MaxThreads] -> Unpinned[MaxThreads] | Neutralized[MaxThreads] as UnpinResult[MaxThreads]
    Neutralized[MaxThreads] -> Unpinned[MaxThreads]
```

When you `import debra`, these typestates become available. Your code using `pin()` and `unpin()` is compile-time verified.

## Composing with Your Typestates

Your application can define its own typestates and compose with library typestates:

```nim
import typestates
import debra
import ./item_processing  # Your item lifecycle typestate

typestate MyDataStructure[T]:
  states Empty[T], NonEmpty[T]
  transitions:
    Empty[T] -> NonEmpty[T]
    NonEmpty[T] -> Empty[T] | NonEmpty[T] as PopResult[T]
  bridges:
    # Bridge to your processing pipeline
    NonEmpty[T] -> item_processing.Item[T].Unprocessed[T]
```

Inside your operations, you use DEBRA's typestates:

```nim
proc pop[T](ds: NonEmpty[T]): (PopResult[T], Unprocessed[T]) {.transition.} =
  # DEBRA typestates enforced here
  let pinned = debra.unpinned(handle).pin()
  # ... do work ...
  let unpinResult = pinned.unpin()
  # Must handle neutralization - compiler enforces this
  case unpinResult.kind:
  of uUnpinned: discard
  of uNeutralized: discard unpinResult.neutralized.acknowledge()
```

## Module-Qualified Bridge Syntax

Use dotted notation to reference typestates from other modules:

```nim
bridges:
  # Same module
  StateA -> OtherTypestate.TargetState

  # Different module
  StateB -> othermodule.Typestate.State

  # With generics
  StateC[T] -> processing.Item[T].Unprocessed[T]
```

## Benefits

- **Type-safe composition**: Your states + library states, all verified
- **No runtime overhead**: Compile-time only
- **Clear contracts**: Library protocol is explicit in types
- **Nested enforcement**: Library typestates work inside your operations
