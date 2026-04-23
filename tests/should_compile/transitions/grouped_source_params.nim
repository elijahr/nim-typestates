## Test: `{.transition.}` still extracts the source type correctly when
## the first parameter group contains multiple identifiers sharing a type.
##
## Regression bar: the source-type extractor must read the type node out
## of `nnkIdentDefs`, not the second identifier. For `proc m(a, b: A)`
## the AST is `IdentDefs(a, b, A, Empty)`, so the naive `firstParam[1]`
## points at `b` and the pragma used to report "b is not part of any
## registered typestate" instead of validating the A -> B edge.
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

proc merge(a, b: A): B {.transition.} =
  B(Flow(a))

let a1 = A(Flow(step: 1))
let a2 = A(Flow(step: 2))
let merged = merge(a1, a2)
doAssert merged is B
echo "grouped_source_params test passed"
