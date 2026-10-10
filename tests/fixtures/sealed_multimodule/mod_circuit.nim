import ../../../src/typestates

type
  Circuit* = object
  Closed* = distinct Circuit
  Open* = distinct Circuit

typestate Circuit:
  states Closed, Open
  transitions:
    Open -> Closed

proc closeCircuit*(c: sink Open): Closed {.transition.} =
  Closed(c.Circuit)
