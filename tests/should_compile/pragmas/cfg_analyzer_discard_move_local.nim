## Test (CFG-001 negative — `discard move(f)` intrinsic-callee consumption,
## round-3 Finding #3, verify.nim:447): a bare `discard move(f)` /
## `discard sink(f)` consumes the tracked local `f` even though `move` /
## `sink` are NOT registered transitions.
##
## Pre-fix the analyzer's discard handler only resolved the operand when
## `opnd.kind in {nnkIdent, nnkSym}` — a wrapper like `move(f)` fell
## through the resolution and left `f` tracked at the fall-through edge,
## false-firing CFG-001 on the canonical Nim ownership-transfer pattern.
##
## Post-fix the discard handler detects the intrinsic-consumer wrapper
## (via `isIntrinsicConsumer(opnd[0])`) and routes through
## `extractTrackedLocal` to the underlying local, dropping it
## unconditionally — `move(f)`'s value goes to the discarded temporary
## whose destructor (if any) fires there, not on the original local.
import ../../../src/typestates

type
  Resource = object
    n: int

  Open = distinct Resource
  Closed = distinct Resource

typestate Resource:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Closed

proc shutdown(r: sink Open): Closed {.transition.} =
  result = Closed(r.Resource)

proc useDiscardMove() {.notATransition.} =
  ## Canonical bare intrinsic-callee consumption: `discard move(f)` —
  ## `f` is consumed by the move; the discarded temporary takes the
  ## destructor (or, here, no destructor, but the discard is the end of
  ## life). Post-fix `f` is dropped from tracking and the fall-through
  ## exit edge accepts.
  var f: Open
  f = Open(Resource(n: 1))
  discard move(f)

verifyTypestates()
useDiscardMove()
echo "cfg_analyzer_discard_move_local ok"
