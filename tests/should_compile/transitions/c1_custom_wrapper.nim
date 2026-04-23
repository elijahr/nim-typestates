## Test: A user-defined generic wrapper marked {.transparentWrapper.} and
## registered via `static: registerTransparentWrapper("MyWrapper")` is
## unwrapped by the transition validator.
import ../../../src/typestates

type MyWrapper*[T] {.transparentWrapper.} = object
  value: T

static:
  registerTransparentWrapper("MyWrapper")

type
  Flow = object
    step: int

  A = distinct Flow
  B = distinct Flow

typestate Flow:
  consumeOnTransition = false
  strictTransitions = false
  states A, B
  transitions:
    A -> B

proc advance(s: A): MyWrapper[B] {.transition.} =
  MyWrapper[B](value: B(Flow(s)))

let a = A(Flow(step: 1))
let w = a.advance()
doAssert w.value is B
echo "c1_custom_wrapper test passed"
