## Test: async transition with undeclared destination must fail.
##
## `Future[SomeOtherState]` unwraps to `SomeOtherState`. The typestate
## declares only Disconnected -> Connecting, so `Disconnected ->
## SomeOtherState` is NOT a declared edge. The diagnostic must name
## `SomeOtherState` and explain that it is not a declared source/dest
## in the typestate.
# expects: "SomeOtherState"
# expects: "is not a declared source"
import chronos
import ../../../src/typestates

type
  Socket = object
    fd: int

  Disconnected = distinct Socket
  Connecting = distinct Socket
  SomeOtherState = distinct Socket

typestate Socket:
  consumeOnTransition = false
  strictTransitions = false
  states Disconnected, Connecting, SomeOtherState
  transitions:
    Disconnected -> Connecting

proc bad(c: Disconnected): Future[SomeOtherState] {.async, transition.} =
  return SomeOtherState(Socket(c))
