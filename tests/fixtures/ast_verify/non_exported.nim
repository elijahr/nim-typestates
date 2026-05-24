## AST-verify fixture (GROUP C, robustness): an UNMARKED *private* (non-
## exported) proc on a strict typestate param. Visibility does not exempt a
## proc from transition marking.
##
## Correct (AST) result: ONE `fcUnmarkedProcStrict` error.
##
## Old text scanner: handles the single-line shape today (it does not key on
## the `*` export marker). Included as a robustness control so the AST rewrite
## continues to flag non-exported procs.
import ../../../src/typestates

type
  Session = object
  Anon = distinct Session
  Auth = distinct Session

typestate Session:
  consumeOnTransition = false
  states Anon, Auth
  transitions:
    Anon -> Auth

proc internalHelper(s: Anon): int =
  result = 7
