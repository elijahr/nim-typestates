## Test: A transparent wrapper (Result) containing a parenthesized union
## destination validates every branch individually.
##
## `Result[(PreChecked | Rejected), string]` must unwrap to `(PreChecked
## | Rejected)`, then strip the paren so each union branch is matched
## against the transition graph. Without the `nnkPar` strip in
## `extractAllTypeNames`, the literal `"(PreChecked | Rejected)"` would
## miss the graph entirely and produce a spurious undeclared-transition
## diagnostic.
import results
import ../../../src/typestates

type
  Order = object
    id: int

  Proposed = distinct Order
  PreChecked = distinct Order
  Rejected = distinct Order

typestate Order:
  consumeOnTransition = false
  strictTransitions = false
  states Proposed, PreChecked, Rejected
  transitions:
    Proposed -> PreChecked
    Proposed -> Rejected

proc preCheck(p: Proposed): Result[(PreChecked | Rejected), string] {.transition.} =
  # Nim treats `(A | B)` at the T position of Result as `void`, so the
  # only generally callable Result constructor here is `err`. That is a
  # Nim type-system limit, not a typestate-pragma one. The important
  # thing this test proves is that the pragma accepts the parenthesized
  # union destination and validates each branch (Proposed -> PreChecked
  # and Proposed -> Rejected) rather than rejecting the unwrapped
  # `"(PreChecked | Rejected)"` string as an undeclared transition.
  err("not ready")

let p = Proposed(Order(id: 1))
let r = p.preCheck()
doAssert r.isErr
echo "wrapper_result_paren_union test passed"
