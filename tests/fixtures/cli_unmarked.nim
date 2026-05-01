## Strict-mode unmarked-proc fixture. Should produce one error
## (fcUnmarkedProcStrict) AND a warning (Iso is an orphan), exercising the
## "errors AND warnings" row of the --warnings-as-errors exit-code matrix.
## Parsed by the CLI ast_parser; not compiled by the comprehensive runner.
import ../../src/typestates

type
  StrictDoor = object
  Closed = distinct StrictDoor
  Open = distinct StrictDoor
  Iso = distinct StrictDoor

typestate StrictDoor:
  consumeOnTransition = false
  strictTransitions = true
  states Closed, Open, Iso
  initial:
    Closed
  terminal:
    Open
  transitions:
    Closed -> Open

# Missing {.transition.} pragma in strict mode -> error.
proc bogus(d: Closed): Open =
  Open(StrictDoor(d))
