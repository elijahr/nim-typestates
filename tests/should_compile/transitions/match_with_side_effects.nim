## F4: match inside proc with var capture and side effects.
import ../../../src/typestates

type
  X = object
    n: int

  Created = distinct X
  Approved = distinct X
  Declined = distinct X

typestate X:
  states Created, Approved, Declined
  transitions:
    Created -> (Approved | Declined) as Result

proc process(p: sink Created): Result {.transition.} =
  Result(kind: rApproved, approved: Approved(X(p)))

proc handler(r: sink Result): int =
  var counter = 0
  match r:
    Approved(aval):
      counter += 1
    Declined(bval):
      counter += 10
  counter

doAssert handler(Created(X(n: 7)).process()) == 1
echo "match_with_side_effects test passed"
