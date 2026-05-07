## Single-target match with a doc comment inside the match block.
## Regression: nnkCommentStmt nodes inside the arms StmtList must be filtered
## out before the "exactly one arm" check, so users can document arms inline
## without tripping the multi-arm error.
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

var a = Created(Doc(body: "ok")).approve()
var label = ""
match a:
  ## doc comment inside the match block — must be filtered, not counted as an arm
  Approved(x):
    label = Doc(x).body
doAssert label == "ok"
echo "match_single_target_with_comment test passed"
