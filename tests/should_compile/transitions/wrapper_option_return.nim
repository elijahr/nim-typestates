## Test: {.transition.} validates through an Option[T] wrapper.
##
## `Option[B]` should unwrap to `B`, so the A -> B edge is matched.
import std/options
import ../../../src/typestates

type
  Pipeline = object
    step: int

  A = distinct Pipeline
  B = distinct Pipeline

typestate Pipeline:
  consumeOnTransition = false
  strictTransitions = false
  states A, B
  transitions:
    A -> B

proc tryAdvance(s: A): Option[B] {.transition.} =
  some(B(Pipeline(s)))

let a = A(Pipeline(step: 1))
let r = a.tryAdvance()
doAssert r.isSome
doAssert r.get is B
echo "wrapper_option_return test passed"
