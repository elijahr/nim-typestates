type
  Payment = object
    id: string
  Created = distinct Payment
  Authorized = distinct Payment
  Captured = distinct Payment

typestate Payment:
  opaqueStates = false
  states Created, Authorized, Captured
  initial Created
  transitions:
    Created -> Authorized
    Authorized -> Captured
