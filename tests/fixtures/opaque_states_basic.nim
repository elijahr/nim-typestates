type
  Payment = object
    id: string
  Created = distinct Payment
  Authorized = distinct Payment
  Captured = distinct Payment

typestate Payment:
  opaqueStates = true
  states Created, Authorized, Captured
  initial Created
  transitions:
    Created -> Authorized
    Authorized -> Captured
