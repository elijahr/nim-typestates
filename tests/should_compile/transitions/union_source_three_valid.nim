## Test: Union source with three valid sources all reaching one destination.
##
## Regression bar for `nnkInfix |` associativity in the source-extraction
## code path. A | B | C parses as `(A | B) | C`; the recursive extractor
## must flatten both halves so ALL three sources are validated against the
## transition graph, not just two.
import ../../../src/typestates

type
  Pipeline = object
    step: int

  A = distinct Pipeline
  B = distinct Pipeline
  C = distinct Pipeline
  D = distinct Pipeline

typestate Pipeline:
  consumeOnTransition = false
  strictTransitions = false
  states A, B, C, D
  transitions:
    A -> D
    B -> D
    C -> D

proc advance(p: A | B | C): D {.transition.} =
  D(Pipeline(p))

let a = A(Pipeline(step: 1))
let d = a.advance()
doAssert d is D
echo "union_source_three_valid test passed"
