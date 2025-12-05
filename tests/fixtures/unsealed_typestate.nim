## Fixture: Explicitly unsealed typestate for extension testing
import ../../src/typestates

type
  Workflow* = object
    step*: int
  Pending* = distinct Workflow
  InProgress* = distinct Workflow
  Done* = distinct Workflow

typestate Workflow:
  isSealed = false
  strictTransitions = false
  states Pending, InProgress, Done
  transitions:
    Pending -> InProgress
    InProgress -> Done
