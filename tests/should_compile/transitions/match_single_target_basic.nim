## Baseline single-target match in non-generic context.
## Verifies that `match` on a single-target transition return rewrites into
## `block: let bind = move(value); body` and the bound variable is usable
## inside the arm body.
import ../../../src/typestates

type
  Doc = object
    body: string
  Created = distinct Doc
  Approved = distinct Doc

typestate Doc:
  states Created, Approved
  transitions:
    Created -> Approved

proc approve(c: sink Created): Approved {.transition.} =
  Approved(Doc(c))

let a = Created(Doc(body: "ok")).approve()
var label = ""
match a:
  Approved(x):
    label = Doc(x).body
doAssert label == "ok"
echo "match_single_target_basic test passed"
