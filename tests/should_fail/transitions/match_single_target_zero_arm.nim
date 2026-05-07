## Single-target match whose body is a single non-Call statement (`discard`).
## A `match a:` block whose body is `discard` parses as
## `nnkCall(match, a, nnkStmtList(discard))` — the StmtList has length 1
## (the `discard` statement) but the arm is not a `Call` shape. The
## validator must reject with a message that names the expected
## `StateName(bindName): body` shape and includes the offending repr.
# expects: "single-target match expects `Approved(bindName): body`, got: discard"
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
match a: # ERROR: arm is `discard`, not `Approved(b): body`
  discard
