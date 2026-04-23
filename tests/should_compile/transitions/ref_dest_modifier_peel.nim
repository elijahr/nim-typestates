## Test: `ref` / `ptr` modifiers on the destination type are peeled
## before the transition graph lookup.
##
## Regression bar: the return-side extractor must peel `ref` / `ptr` /
## `var` / `sink` modifiers before dispatching on the leaf case.
## Before the fix, `proc f(a: A): ref B` reached the `else` arm as
## `["ref B"]`, which never matched the graph and produced a spurious
## "Undeclared transition: A -> ref B" diagnostic.
import ../../../src/typestates

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

proc advanceRef(a: A): ref B {.transition.} =
  new(result)
  result[] = B(Flow(a))

let a = A(Flow(step: 1))
let boxed = a.advanceRef()
doAssert boxed[] is B
echo "ref_dest_modifier_peel test passed"
