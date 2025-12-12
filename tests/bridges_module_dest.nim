## Destination module for bridge tests

import ../src/typestates

type
  DestTypestate* = object
    id*: int

  DestStateA* = distinct DestTypestate
  DestStateB* = distinct DestTypestate

typestate DestTypestate:
  consumeOnTransition = false
  states DestStateA, DestStateB
  transitions:
    DestStateA -> DestStateB
