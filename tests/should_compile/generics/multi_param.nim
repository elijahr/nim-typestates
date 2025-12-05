## Test: Generic typestate with multiple type parameters
import ../../../src/typestates

type
  Pair[K, V] = object
    key: K
    value: V
  EmptyPair[K, V] = distinct Pair[K, V]
  HasKey[K, V] = distinct Pair[K, V]
  Complete[K, V] = distinct Pair[K, V]

typestate Pair[K, V]:
  strictTransitions = false
  states EmptyPair[K, V], HasKey[K, V], Complete[K, V]
  transitions:
    EmptyPair[K, V] -> HasKey[K, V]
    HasKey[K, V] -> Complete[K, V]

proc setKey[K, V](p: EmptyPair[K, V], key: K): HasKey[K, V] {.transition.} =
  var pair = Pair[K, V](p)
  pair.key = key
  HasKey[K, V](pair)

proc setValue[K, V](p: HasKey[K, V], value: V): Complete[K, V] {.transition.} =
  var pair = Pair[K, V](p)
  pair.value = value
  Complete[K, V](pair)

let empty = EmptyPair[string, int](Pair[string, int](key: "", value: 0))
let withKey = empty.setKey("answer")
let complete = withKey.setValue(42)
doAssert Pair[string, int](complete).key == "answer"
doAssert Pair[string, int](complete).value == 42
echo "multi_param test passed"
