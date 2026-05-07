## Branch wrapper type name (`as Approved`) collides with a declared state
## name (`Approved`). The new parser-side validator
## `validateNoBranchTypeStateCollision` must reject this at DSL parse time
## (before codegen) so we never emit two `match*(value: Approved; ...)`
## overloads with the same first-param type.
# expects: "Branch wrapper type name 'Approved' collides with state name 'Approved'"
import ../../../src/typestates

type
  Doc = object
  Created = distinct Doc
  Approved = distinct Doc
  Declined = distinct Doc

typestate Doc:
  states Created, Approved, Declined
  transitions:
    Created -> (Approved | Declined) as Approved   # ERROR: `as Approved` collides with state Approved
