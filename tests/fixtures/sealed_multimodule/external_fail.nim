import mod_door
import ../../../src/typestates

proc hack(d: sink Closed): Open {.transition.} =
  Open(d.Door)
