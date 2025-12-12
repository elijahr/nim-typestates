## Test bridges between generic typestates with module qualifiers
##
## This test verifies that:
## 1. Bridges work with generic source typestates
## 2. Bridges work with generic destination typestates
## 3. Module-qualified syntax works with generics
## 4. Type parameters are properly maintained across bridge transitions

import ../src/typestates

# Generic destination typestate
type
  Storage[T] = object
    data: T

  StorageEmpty[T] = distinct Storage[T]
  StorageFull[T] = distinct Storage[T]

typestate Storage[T]:
  consumeOnTransition = false
  states StorageEmpty[T], StorageFull[T]
  transitions:
    StorageEmpty[T] -> StorageFull[T]

# Generic source typestate with module-qualified bridge to generic destination
type
  Container[T] = object
    value: T
    capacity: int

  ContainerReady[T] = distinct Container[T]
  ContainerProcessed[T] = distinct Container[T]

typestate Container[T]:
  consumeOnTransition = false
  states ContainerReady[T], ContainerProcessed[T]
  transitions:
    ContainerReady[T] -> ContainerProcessed[T]
  bridges:
    # Module-qualified bridge between generic types
    # Note: Bridge declarations use base names (without [T])
    ContainerProcessed -> Storage.StorageEmpty

# Bridge implementation - transfers data from Container to Storage
proc transfer[T](c: ContainerProcessed[T]): StorageEmpty[T] {.transition.} =
  let container = Container[T](c)
  StorageEmpty[T](Storage[T](data: container.value))

# Test with int
block test_generic_bridge_int:
  let container = ContainerProcessed[int](Container[int](value: 42, capacity: 100))
  let storage = transfer(container)
  doAssert Storage[int](storage).data == 42
  echo "Generic bridge works with int"

# Test with string
block test_generic_bridge_string:
  let container = ContainerProcessed[string](Container[string](value: "hello", capacity: 50))
  let storage = transfer(container)
  doAssert Storage[string](storage).data == "hello"
  echo "Generic bridge works with string"

# Test with seq
block test_generic_bridge_seq:
  let container = ContainerProcessed[seq[int]](Container[seq[int]](value: @[1, 2, 3], capacity: 10))
  let storage = transfer(container)
  doAssert Storage[seq[int]](storage).data == @[1, 2, 3]
  echo "Generic bridge works with seq[int]"

echo "All generic module-qualified bridge tests passed"
