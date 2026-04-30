## F4: match on generic branching union.
import ../../../src/typestates

type
  Bucket[T] = object
    items: seq[T]

  Empty[T] = distinct Bucket[T]
  Full[T] = distinct Bucket[T]
  Errored[T] = distinct Bucket[T]

typestate Bucket[T]:
  states Empty[T], Full[T], Errored[T]
  transitions:
    Empty[T] -> (Full[T] | Errored[T]) as FillResult[T]

proc fill(b: sink Empty[int]): FillResult[int] {.transition.} =
  FillResult[int](kind: fFull, full: Full[int](Bucket[int](items: @[1, 2, 3])))

var r = Empty[int](Bucket[int]()).fill()
var label = ""
match r:
  Full(f):
    label = "Full"
  Errored(e):
    label = "Errored"

doAssert label == "Full"
echo "match_branching_generic test passed"
