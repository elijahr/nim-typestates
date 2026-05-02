## Clean typestate fixture for tcli_warnings_as_errors.nim. Has at least one
## state, one transition, and no reachability/strict warnings.
## Parsed by the CLI ast_parser; not compiled by the comprehensive runner.
import ../../src/typestates

type
  Door = object
  Closed = distinct Door
  Open = distinct Door

typestate Door:
  consumeOnTransition = false
  states Closed, Open
  initial:
    Closed
  terminal:
    Open
  transitions:
    Closed -> Open

proc openDoor(d: Closed): Open {.transition.} =
  Open(Door(d))
