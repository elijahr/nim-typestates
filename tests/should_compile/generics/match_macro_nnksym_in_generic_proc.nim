## D1 regression — variant 1/4: original v0.7.0 bug shape.
##
## v0.7.0's `buildMatchCase` required `nnkIdent` arm heads and rejected
## `nnkSym`. In a generic proc body, Nim's sema converts arm-head idents
## (`Approved`, `Declined`) into `nnkSym` symbols before the `match` macro
## runs, so the pre-fix code rejected them. Fixed in v0.7.1.
##
## This fixture sits in tests/should_compile/generics/ (not transitions/)
## to make the multi-fixture D1 matrix visually grouped. It uses a
## branching union over a generic proc body to force the nnkSym path.
import ../../../src/typestates

type
  Doc = object
    body: string

  Created = distinct Doc
  Approved = distinct Doc
  Declined = distinct Doc
  Confirmed = distinct Doc
  Rejected = distinct Doc

typestate Doc:
  states Created, Approved, Declined, Confirmed, Rejected
  transitions:
    Created -> (Approved | Declined) as Decision
    Approved -> Confirmed
    Declined -> Rejected

proc decide(d: sink Created): Decision {.transition.} =
  if Doc(d).body == "ok":
    Decision(kind: dApproved, approved: Approved(Doc(d)))
  else:
    Decision(kind: dDeclined, declined: Declined(Doc(d)))

proc confirm(a: sink Approved): Confirmed {.transition.} =
  Confirmed(Doc(a))

proc reject(r: sink Declined): Rejected {.transition.} =
  Rejected(Doc(r))

# Generic proc body — arm-head Approved/Declined arrive as nnkSym after sema.
proc dispatch[T](d: sink Created, ok: T, bad: T): T =
  var r = d.decide()
  var label: T
  match r:
    Approved(a):
      let c = a.confirm()
      doAssert Doc(c).body == "ok"
      label = ok
    Declined(x):
      let rj = x.reject()
      # The Declined branch is only reached when body != "ok"; preserve
      # the actual input string so the assertion is meaningful across both
      # call-site instantiations below.
      doAssert Doc(rj).body != "ok"
      label = bad
  label

doAssert dispatch[string](Created(Doc(body: "ok")), "yes", "no") == "yes"
doAssert dispatch[string](Created(Doc(body: "x")), "yes", "no") == "no"
echo "match_macro_nnksym_in_generic_proc test passed"
