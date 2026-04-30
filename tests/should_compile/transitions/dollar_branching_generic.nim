## F3: $ overload for branching union types under a generic typestate.
## Exercises the `branchTypeNode.copyNimTree` path so the generated proc
## binds correctly under generic instantiation (`FillResult[int]`).
import ../../../src/typestates

type
  Bucket[T] = object
    items: seq[T]

  Empty[T] = distinct Bucket[T]
  Full[T] = distinct Bucket[T]
  Error[T] = distinct Bucket[T]

typestate Bucket[T]:
  consumeOnTransition = false
  states Empty[T], Full[T], Error[T]
  transitions:
    Empty[T] -> (Full[T] | Error[T]) as FillResult[T]

# Full branch
block:
  let r = FillResult[int](kind: fFull, full: Full[int](Bucket[int](items: @[1])))
  doAssert $r == "Full"

# Error branch
block:
  let r = FillResult[int](kind: fError, error: Error[int](Bucket[int]()))
  doAssert $r == "Error"

echo "dollar_branching_generic test passed"
