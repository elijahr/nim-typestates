## Test: Mix of generic and simple states
import ../../../src/typestates

type
  Hybrid[T] = object
    data: T

  SimpleState = distinct Hybrid[int]
  GenericState[T] = distinct Hybrid[T]

# Note: This tests whether mixed generic/simple states work
# The typestate macro should handle both

type
  HybridInt = Hybrid[int]
  GenericInt = GenericState[int]

# For now just verify types compile
let s = SimpleState(Hybrid[int](data: 42))
doAssert Hybrid[int](s).data == 42
echo "mixed_generic_simple test passed"
