## Test (TA-002): the initial-state argument is not a state of the named
## typestate.
##
## `typestate ConnState:` declares states {Listening, Closed}. The
## attachment pragma references `NotARealState` which is not in that
## set. The TA-002 message must call out the typestate name and the
## bogus state name.
# expects: "is not a state of typestate"
# expects: "ConnState"
# expects: "NotARealState"
import ../../../src/typestates

type
  Listening = object
  Closed = object

typestate ConnState:
  consumeOnTransition = false
  strictTransitions = false
  states Listening, Closed
  initial:
    Listening
  terminal:
    Closed
  transitions:
    Listening -> Closed

type Server {.ConnState: NotARealState.} = object
  port: int
