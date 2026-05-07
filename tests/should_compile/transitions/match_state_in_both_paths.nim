## A state used BOTH as a branching-arm of one transition AND as a single-
## target return of another. Verifies that the branching `match` overload
## (keyed on the wrapper type, e.g. `Decision`) and the single-target
## `match` overload (keyed on the bare state type, e.g. `Approved`) both
## dispatch correctly, since Nim disambiguates by the typed first param.
import ../../../src/typestates

type
  Doc = object
    body: string
  Created = distinct Doc
  Approved = distinct Doc
  Declined = distinct Doc
  Confirmed = distinct Doc

typestate Doc:
  states Created, Approved, Declined, Confirmed
  transitions:
    Created -> (Approved | Declined) as Decision
    Approved -> Confirmed                       # single-target return
    Declined -> Approved                        # rehab path: single-target return of Approved

proc decide(d: sink Created): Decision {.transition.} =
  # dApproved: prefix 'd' from branchEnumPrefix(Decision) + state name 'Approved'.
  # The prefix is the lowercased first char of the branch wrapper type name,
  # emitted by `branchEnumPrefix` in src/typestates/codegen.nim.
  Decision(kind: dApproved, approved: Approved(Doc(d)))

proc rehab(d: sink Declined): Approved {.transition.} =
  Approved(Doc(d))

# Path 1: branching match dispatches Decision via kind discriminator.
var label1 = ""
let dec = Created(Doc(body: "x")).decide()
match dec:
  Approved(a):
    label1 = "approved-via-decision:" & Doc(a).body
  Declined(_d):
    label1 = "declined"
doAssert label1 == "approved-via-decision:x"

# Path 2: single-target match on a bare Approved value (from rehab).
let bareApproved = Declined(Doc(body: "z")).rehab()
var label2 = ""
match bareApproved:
  Approved(a):
    label2 = "approved-via-rehab:" & Doc(a).body
doAssert label2 == "approved-via-rehab:z"

echo "match_state_in_both_paths test passed"
