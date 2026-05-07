## Single-target match where the arm names a state different from the
## value's type. The codegen helper must reject this with a tailored error
## that names both the wrong arm and the expected state.
# expects: "unknown state 'Declined' for single-target match; expected 'Approved'"
import ../../../src/typestates

type
  Doc = object
  Created = distinct Doc
  Approved = distinct Doc
  Declined = distinct Doc

typestate Doc:
  states Created, Approved, Declined
  transitions:
    Created -> Approved
    Created -> Declined

proc approve(c: sink Created): Approved {.transition.} =
  Approved(Doc(c))

let a = Created(Doc()).approve()
match a:
  Declined(_x):    # ERROR: Declined arm on Approved value
    discard
