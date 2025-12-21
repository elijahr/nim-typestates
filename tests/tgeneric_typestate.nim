## Test generic typestate support.
##
## Verifies that typestates with generic type parameters work correctly.

import ../src/typestates

# Test 1: Basic generic typestate
type
  Container[T] = object
    value: T

  Empty[T] = distinct Container[T]
  Full[T] = distinct Container[T]

typestate Container[T]:
  consumeOnTransition = false # Opt out for existing tests
  states Empty[T], Full[T]
  transitions:
    Empty[T] -> Full[T]
    Full[T] -> Empty[T]

proc fill[T](c: Empty[T], val: T): Full[T] {.transition.} =
  var cont = Container[T](c)
  cont.value = val
  result = Full[T](cont)

proc emptyContainer[T](c: Full[T]): Empty[T] {.transition.} =
  result = Empty[T](Container[T](c))

# Test 2: Multiple type parameters
type
  KeyValue[K, V] = object
    key: K
    value: V

  EmptyKV[K, V] = distinct KeyValue[K, V]
  HasKey[K, V] = distinct KeyValue[K, V]
  HasBoth[K, V] = distinct KeyValue[K, V]

typestate KeyValue[K, V]:
  consumeOnTransition = false # Opt out for existing tests
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

proc clear[K, V](kv: HasBoth[K, V]): EmptyKV[K, V] {.transition.} =
  result = EmptyKV[K, V](KeyValue[K, V](kv))

# Test 3: notATransition with generics
proc peek[T](c: Full[T]): T {.notATransition.} =
  Container[T](c).value

# Run tests
block test1:
  let e = Empty[int](Container[int](value: 0))
  let f = e.fill(42)
  doAssert Container[int](f).value == 42
  let e2 = f.emptyContainer()
  echo "Test 1: Basic generic typestate - PASSED"

block test2:
  let e = Empty[string](Container[string](value: ""))
  let f = e.fill("hello")
  doAssert Container[string](f).value == "hello"
  echo "Test 2: Generic with different type - PASSED"

block test3:
  let kv = EmptyKV[string, int](KeyValue[string, int](key: "", value: 0))
  let withKey = kv.setKey("mykey")
  let withBoth = withKey.setValue(42)
  doAssert KeyValue[string, int](withBoth).key == "mykey"
  doAssert KeyValue[string, int](withBoth).value == 42
  let cleared = withBoth.clear()
  echo "Test 3: Multiple type parameters - PASSED"

block test4:
  let f = Full[int](Container[int](value: 99))
  doAssert f.peek() == 99
  echo "Test 4: notATransition with generics - PASSED"

echo "All generic typestate tests passed!"
