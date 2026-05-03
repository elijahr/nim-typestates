## Regression: `match` macro must work when invoked from inside the body of a
## generic proc or generic template. In v0.7.0, `buildMatchCase` required
## `nnkIdent` for arm-head and rejected the `nnkSym` / `nnkOpenSymChoice`
## nodes that Nim's sema produces for arm heads in generic contexts.
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

# --- Scenario 1: generic proc body invokes match ---------------------------
#
# When `runDecision` is instantiated with `T = string`, Nim's sema runs over
# its body and converts the arm-head idents `Approved` / `Declined` into
# nnkSym (or, if Decision is shadowed by a different overload, nnkOpenSymChoice).
# The pre-fix `buildMatchCase` rejected those node kinds outright.
proc runDecision[T](d: sink Created, ok: T, bad: T): T =
  var r = d.decide()
  var label: T
  match r:
    Approved(a):
      let c = a.confirm()
      doAssert Doc(c).body == "ok"
      label = ok
    Declined(x):
      let rj = x.reject()
      doAssert Doc(rj).body == "no"
      label = bad
  label

doAssert runDecision[string](
  Created(Doc(body: "ok")), "approved-confirmed", "declined-rejected"
) == "approved-confirmed"
doAssert runDecision[string](
  Created(Doc(body: "no")), "approved-confirmed", "declined-rejected"
) == "declined-rejected"

# --- Scenario 2: generic template body invokes match -----------------------
#
# Templates are expanded into their call site, and when the call site is
# itself a generic proc the symchoice resolution still happens before the
# `match` macro runs. This exercises a different AST shape than scenario 1.
template processWith[T](src: sink Created, okVal: T, badVal: T): T =
  block:
    var rr = src.decide()
    var outLabel: T
    match rr:
      Approved(aa):
        let cc = aa.confirm()
        doAssert Doc(cc).body == "ok"
        outLabel = okVal
      Declined(xx):
        let rrj = xx.reject()
        doAssert Doc(rrj).body == "no"
        outLabel = badVal
    outLabel

proc runViaTemplate[T](d: sink Created, ok: T, bad: T): T =
  processWith[T](d, ok, bad)

doAssert runViaTemplate[int](Created(Doc(body: "ok")), 1, 2) == 1
doAssert runViaTemplate[int](Created(Doc(body: "no")), 1, 2) == 2

echo "match_generic_call_site test passed"
