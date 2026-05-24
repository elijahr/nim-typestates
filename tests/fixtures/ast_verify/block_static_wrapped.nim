## AST-verify fixture (FINDING 1 — collectRoutineDefs container coverage):
## UNMARKED typestate-parameter routines defined inside statement-container
## nodes that `collectRoutineDefs` previously did NOT descend into — a `static:`
## block and a `block:` statement — on a STRICT typestate.
##
## Correct (AST) result: TWO `fcUnmarkedProcStrict` errors (one per wrapped
## routine).
##
## Before the fix: FALSE-NEGATIVE (ZERO findings). `collectRoutineDefs` only
## descended `nkStmtList`/`when`-branches, so routines wrapped in
## `nkStaticStmt` / `nkBlockStmt` were silently skipped — exactly the
## silent-skip class the AST rewrite exists to eliminate.
import ../../../src/typestates

type
  Door = object
  Open = distinct Door
  Closed = distinct Door

typestate Door:
  consumeOnTransition = false
  states Open, Closed
  transitions:
    Open -> Closed

static:
  proc wrappedInStatic(d: var Open) =
    discard

block:
  proc wrappedInBlock(d: var Open) =
    discard
