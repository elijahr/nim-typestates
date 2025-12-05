## Fixture: Session typestate for bridge testing
import ../../src/typestates

type
  Session* = object
    userId*: string
    timeout*: int
  Active* = distinct Session
  Expired* = distinct Session
  Guest* = distinct Session

typestate Session:
  strictTransitions = false
  states Active, Expired, Guest
  transitions:
    Active -> Expired
    Guest -> Active
    * -> Expired
