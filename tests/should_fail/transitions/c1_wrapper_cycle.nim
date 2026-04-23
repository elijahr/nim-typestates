## Test: Transparent-wrapper cycle detection.
##
## Two user wrappers W1 and W2 are both registered as transparent. The
## transition's return type is `W1[W2[W1[X]]]` — unwrapping walks
## W1 -> W2 -> W1, at which point the cycle detector fires because W1
## appears twice in the unwrap stack. The diagnostic must contain the
## phrase `transparent wrapper cycle`.
# expects: "transparent wrapper cycle"
import ../../../src/typestates

type
  W1*[T] {.transparentWrapper.} = object
    value: T
  W2*[T] {.transparentWrapper.} = object
    value: T

static:
  registerTransparentWrapper("W1")
  registerTransparentWrapper("W2")

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

proc advance(s: A): W1[W2[W1[B]]] {.transition.} =
  discard
