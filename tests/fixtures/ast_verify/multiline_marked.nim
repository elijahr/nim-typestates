## AST-verify fixture (GROUP A): a STRICT typestate with a proc whose header
## spans multiple lines. The param is on its own line and the return type plus
## `{.transition.}` pragma are on a LATER line. This IS a valid transition.
##
## Correct (AST) result: NO finding for `advance`.
##
## Old text scanner: the line that starts with `proc ` does NOT contain the
## `{.transition.}` substring (it lives on a later line), and may not even
## carry the typestate param on that line — so the scanner's per-line model
## cannot reason about this shape. It happens to emit nothing here only by
## accident of the param not appearing on the `proc` line; the linchpin
## RED case is `multiline_unmarked.nim`.
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

proc advance(
    m: Idle
): Running {.transition.} =
  result = Running(m)
