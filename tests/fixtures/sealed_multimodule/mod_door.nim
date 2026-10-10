import ../../../src/typestates

type
  Door* = object
  Closed* = distinct Door
  Open* = distinct Door

typestate Door:
  states Closed, Open
  transitions:
    Closed -> Open

proc openDoor*(d: sink Closed): Open {.transition.} =
  Open(d.Door)
