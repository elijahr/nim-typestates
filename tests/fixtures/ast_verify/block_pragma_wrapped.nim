## AST-verify fixture (Gemini medium — collectRoutineDefs pragma-block coverage):
## UNMARKED typestate-parameter routine defined inside a block-pragma section
## (`{.cast(gcsafe).}:`) on a STRICT typestate.
##
## Correct (AST) result: ONE `fcUnmarkedProcStrict` error.
##
## Before the fix: FALSE-NEGATIVE (ZERO findings). The routine parses as
## `nkPragmaBlock -> nkStmtList -> nkProcDef`, and `collectRoutineDefs` did NOT
## descend `nkPragmaBlock`, so the routine was silently skipped — the same
## silent-skip class the AST rewrite exists to eliminate. This is the exact
## downstream shape (`{.push raises: [].}` / block-pragma sections) that
## nim-debra / lockfreequeues use.
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

{.cast(gcsafe).}:
  proc wrappedInBlockPragma(d: var Open) =
    discard
