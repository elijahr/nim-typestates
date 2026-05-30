## AST-verify fixture (Gemini medium — collectRoutineDefs case-branch coverage):
## UNMARKED typestate-parameter routines defined inside `case`/`of`/`else`
## branches on a STRICT typestate.
##
## Correct (AST) result: TWO `fcUnmarkedProcStrict` errors (one per branch).
##
## Before the fix: FALSE-NEGATIVE (ZERO findings). `collectRoutineDefs` did NOT
## descend `nkCaseStmt`/`nkOfBranch`, so routines wrapped in a module-scope
## `case` were silently skipped — the same silent-skip class the AST rewrite
## exists to eliminate.
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

const pick = 1

case pick
of 1:
  proc wrappedInOf(d: var Open) =
    discard
else:
  proc wrappedInElse(d: var Open) =
    discard
