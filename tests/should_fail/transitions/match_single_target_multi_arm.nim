## Single-target match given more than one arm. The codegen helper must
## reject with a tailored error noting the count and that single-target
## match accepts exactly one arm.
# expects: "single-target match accepts exactly one arm; got 2"
import ../../../src/typestates

type
  Doc = object
  Created = distinct Doc
  Approved = distinct Doc

typestate Doc:
  states Created, Approved
  transitions:
    Created -> Approved

proc approve(c: sink Created): Approved {.transition.} =
  Approved(Doc(c))

let a = Created(Doc()).approve()
match a:
  Approved(x):
    discard x
  Approved(y):       # ERROR: second arm
    discard y
