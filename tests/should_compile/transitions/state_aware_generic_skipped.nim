## F5: Generic typestates are deferred to v0.6 and must NOT have decoys
## emitted. The decoy codegen needs generic-parameter threading that v0.5
## intentionally skips. This fixture confirms a generic typestate compiles
## cleanly with the F5 logic in place.
import ../../../src/typestates

type
  Container[T] = object
    value: T

  Empty[T] = distinct Container[T]
  Full[T] = distinct Container[T]

typestate Container[T]:
  consumeOnTransition = false
  strictTransitions = false
  states Empty[T], Full[T]
  transitions:
    Empty[T] -> Full[T]

proc fill(e: sink Empty[int], v: int): Full[int] {.transition.} =
  Full[int](Container[int](value: v))

verifyTypestates()

let e = Empty[int](Container[int]())
let f = e.fill(42)
doAssert f is Full[int]

echo "state_aware_generic_skipped test passed"
