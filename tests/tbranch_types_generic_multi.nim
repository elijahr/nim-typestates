## Test generic branch types with multiple type parameters.

import std/unittest
import ../src/typestates

# Use object types instead of distinct to avoid Nim compiler bug with
# distinct types and multiple generic parameters
type
  Map[K, V] = object
    key: K
    value: V
    state: int  # Used to track state

  EmptyMap[K, V] = object
    inner: Map[K, V]

  HasItems[K, V] = object
    inner: Map[K, V]

  MapError[K, V] = object
    inner: Map[K, V]

typestate Map[K, V]:
  states EmptyMap[K, V], HasItems[K, V], MapError[K, V]
  transitions:
    EmptyMap[K, V] -> HasItems[K, V] | MapError[K, V] as InsertResult[K, V]
    HasItems[K, V] -> EmptyMap[K, V]

suite "Generic Branch Types - Multiple Params":
  test "MapState enum exists":
    check fsEmptyMap is MapState
    check fsHasItems is MapState
    check fsMapError is MapState

  test "state procs work with multiple params":
    let e = EmptyMap[string, int](inner: Map[string, int](key: "", value: 0, state: 0))
    let h = HasItems[string, int](inner: Map[string, int](key: "foo", value: 42, state: 1))

    check e.state == fsEmptyMap
    check h.state == fsHasItems

  test "InsertResultKind enum exists":
    check iHasItems is InsertResultKind
    check iMapError is InsertResultKind

  test "InsertResult[K, V] type exists and is constructible":
    let b1 = InsertResult[string, int](
      kind: iHasItems,
      hasitems: HasItems[string, int](inner: Map[string, int](key: "foo", value: 42, state: 1))
    )
    check b1.kind == iHasItems
    check b1.hasitems.inner.key == "foo"
    check b1.hasitems.inner.value == 42

  test "toInsertResult constructors work":
    let hasItems = HasItems[string, int](inner: Map[string, int](key: "foo", value: 42, state: 1))
    let mapError = MapError[string, int](inner: Map[string, int](key: "", value: 0, state: 2))

    let b1 = toInsertResult(hasItems)
    check b1.kind == iHasItems
    check b1.hasitems.inner.key == "foo"

    let b2 = toInsertResult(mapError)
    check b2.kind == iMapError

  test "-> operator works with multiple params":
    let hasItems = HasItems[string, int](inner: Map[string, int](key: "foo", value: 42, state: 1))

    let b1 = InsertResult[string, int] -> hasItems
    check b1.kind == iHasItems
    check b1.hasitems.inner.key == "foo"
