## AST-verify fixture (GROUP A, LINCHPIN green-mirage guard): a STRICT
## typestate with a proc whose header spans multiple lines, the typestate
## param on its own line, and NO `{.transition.}` / `{.notATransition.}`
## pragma anywhere. On a strict typestate this MUST be flagged.
##
## Correct (AST) result: exactly ONE `fcUnmarkedProcStrict` error, anchored
## to the proc's definition line (the `proc mutate(` line).
##
## Old text scanner: MISSES this entirely. The `proc ` line has no `(`+param
## type on it (the param `m: Idle` is on the next line), so the scanner never
## extracts `Idle`, never matches the typestate, and emits nothing. That false
## "all clear" is the green mirage the AST rewrite must eliminate.
import ../../../src/typestates

type
  Machine = object
  Idle = distinct Machine
  Running = distinct Machine

typestate Machine:
  consumeOnTransition = false
  states Idle, Running
  transitions:
    Idle -> Running

proc mutate(
    m: Idle
): string =
  result = "leaked through the green mirage"
