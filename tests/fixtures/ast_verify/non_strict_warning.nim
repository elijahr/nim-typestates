## AST-verify fixture (GROUP B / severity control): a typestate with
## `strictTransitions = false` and an UNMARKED proc on a typestate param.
##
## Correct result: ONE `fcUnmarkedProc` WARNING (severity = warning), NOT an
## error. The non-strict mode downgrades unmarked procs to advisory warnings.
##
## Old text scanner: handles this case correctly today (single-line param,
## plain pragma block). It is included as a severity-routing control so the
## AST rewrite does not regress strict-vs-warning classification.
import ../../../src/typestates

type
  Machine = object
  Idle = distinct Machine
  Running = distinct Machine

typestate Machine:
  consumeOnTransition = false
  strictTransitions = false
  states Idle, Running
  transitions:
    Idle -> Running

proc helper(m: Idle): int =
  result = 42
