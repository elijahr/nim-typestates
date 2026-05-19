## Test (regression fixture for docs/guide/cfg-analyzer.md): the
## "Minimal fix" example from the v0.9.0 CFG analyzer migration guide
## must compile clean under the post-Finding-#1 analyzer.
##
## This fixture mirrors the doc example verbatim (modulo same-name
## typestate warning suppression — the doc text uses Connection /
## Connection which trips the same-name warning; we use a distinct
## typestate name here to keep the fixture noise-free while preserving
## the call/asgn shapes that the analyzer must track).
##
## The migration guide promises this pattern works post-0.9.0:
##
##   proc handle(cond: bool) {.notATransition.} =
##     var c = Active(Connection())
##     if cond:
##       discard close(move c)
##       return
##     discard close(move c)
##
## Both branches `discard close(move c)`; the call's transition consumes
## `c` (Active -> Closed terminal); the analyzer recognizes call-tracking
## on both branches; the if/else reconciles cleanly to "c consumed in
## all branches"; the fall-through exit accepts.
import ../../../src/typestates

type
  Conn = object
    n: int

  Active = distinct Conn
  Closed = distinct Conn

typestate ConnContext:
  consumeOnTransition = false
  strictTransitions = false
  states Active, Closed
  initial:
    Active
  terminal:
    Closed
  transitions:
    Active -> Closed

proc close(c: sink Active): Closed {.transition.} =
  ## Registered transition consuming Active, producing terminal Closed.
  result = Closed(c.Conn)

proc handle(cond: bool) {.notATransition.} =
  ## Migration guide "Minimal fix" shape (Connection/Active/Closed
  ## renamed to avoid the same-name typestate diagnostic).
  var c: Active
  if cond:
    discard close(c)
    return
  discard close(c)

verifyTypestates()
echo "cfg_analyzer_migration_guide_minimal_fix ok"
