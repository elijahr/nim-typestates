## Fixture: Shutdown typestate for bridge testing
import ../../src/typestates

type
  Shutdown* = object
    reason*: string
  Terminal* = distinct Shutdown

typestate Shutdown:
  strictTransitions = false
  states Terminal
