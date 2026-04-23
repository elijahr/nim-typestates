## Test: {.transition, async.} (reversed pragma order) is accepted.
##
## Per the F2 empirical spike (chronos 4.2.2 + Nim 2.2.6), both
## `{.async, transition.}` and `{.transition, async.}` produce identical
## signature ASTs from `{.transition.}`'s perspective — the user-written
## `Future[T]` is preserved in both cases. This test covers the
## transition-first ordering (recommended for forward-compat with
## future body-level analysis).
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

proc connect(c: Disconnected): Future[Connecting] {.transition, async.} =
  return Connecting(Socket(c))

let d = Disconnected(Socket(fd: 1))
let fut = d.connect()
let c = waitFor fut
doAssert c is Connecting
echo "c2_transition_async_order test passed"
