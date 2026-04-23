## Test: {.async, transition.} with Future[T] return type.
##
## `Future[Connecting]` should unwrap to `Connecting` so the
## Disconnected -> Connecting edge is matched. Future is registered
## as a built-in transparent wrapper (alongside Result and Option).
import chronos
import ../../../src/typestates

type
  Socket = object
    fd: int

  Disconnected = distinct Socket
  Connecting = distinct Socket

typestate Socket:
  consumeOnTransition = false
  strictTransitions = false
  states Disconnected, Connecting
  transitions:
    Disconnected -> Connecting

proc connect(c: Disconnected): Future[Connecting] {.async, transition.} =
  return Connecting(Socket(c))

let d = Disconnected(Socket(fd: 1))
let fut = d.connect()
let c = waitFor fut
doAssert c is Connecting
echo "c2_async_future test passed"
