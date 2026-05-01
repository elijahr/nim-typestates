## F3: $ overload for generic state types.
import ../../../src/typestates

type
  Container[T] = object
    items: seq[T]

  Empty[T] = distinct Container[T]
  Full[T] = distinct Container[T]

typestate Container[T]:
  consumeOnTransition = false
  states Empty[T], Full[T]
  transitions:
    Empty[T] -> Full[T]

proc fill(c: Empty[int]): Full[int] {.transition.} =
  Full[int](Container[int](items: @[1, 2, 3]))

let e = Empty[int](Container[int]())
doAssert $e == "Empty"

let f = e.fill()
doAssert $f == "Full"
echo "dollar_generic test passed"
