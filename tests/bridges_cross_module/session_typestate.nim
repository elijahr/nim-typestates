## Destination typestate for cross-module bridge test.
## This module is imported by auth_typestate.nim

import ../../src/typestates

type
  Session* = object
    userId*: string
    expires*: int
  Active* = distinct Session
  Guest* = distinct Session
  Expired* = distinct Session

typestate Session:
  states Active, Guest, Expired
  transitions:
    Active -> Expired
    Guest -> Expired

# Helper to create sessions
proc newActiveSession*(userId: string, timeout: int): Active =
  Active(Session(userId: userId, expires: timeout))

proc newGuestSession*(): Guest =
  Guest(Session(userId: "anonymous", expires: 3600))
