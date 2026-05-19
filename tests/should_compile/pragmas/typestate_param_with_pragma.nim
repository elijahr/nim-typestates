## Test: `{.transition.}` param-name extraction handles pragma-decorated
## parameters (`p {.x.}: T`) on a typestate-bearing param.
##
## Round-16 acceptance for Gemini r15's MEDIUM finding #3: the param-name
## extractor in `extractTypestatedParams` (pragmas.nim:445-462) systematically
## peels `nnkPragmaExpr` and `nnkPostfix` wrappers before dispatching on
## the leaf ident shape, mirroring the unwrap precedence used by
## `extractTypeDeclName` (pragmas.nim:1052-1057).
##
## End-to-end shape covered here: `p {.userPragma.}: var Src` — Nim parses
## the param-name slot as `PragmaExpr(Ident, Pragma)`. The pre-round-16
## extractor handled this exact shape, but the new unwrap is the same
## precedence chain that also handles the AccQuoted-in-PragmaExpr shape
## (e.g. ``p` {.userPragma.}: var Src``) covered by the sibling unit
## test `textract_typestated_params_name_shapes.nim`. Both shapes must
## register the param into the typestate-tracked entry set so CFG
## analysis pre-populates `LiveState`.
import ../../../src/typestates

type
  Pipe = object
    fd: int

  Open = distinct Pipe
  Closed = distinct Pipe

typestate Pipe:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Closed

template noopUser() {.pragma.}

proc close(p {.noopUser.}: var Open): Closed {.transition.} =
  Closed(Pipe(p))

let pOpen = Open(Pipe(fd: 7))
var pVar = pOpen
let pClosed = close(pVar)
doAssert pClosed is Closed
echo "typestate_param_with_pragma ok"
