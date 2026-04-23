## Test: Future[Result[T, E]] double-wrapper unwrap.
##
## Both Future and Result are in the built-in transparent-wrapper
## registry. `unwrapTransparent` walks the chain Future -> Result ->
## SentUnacked, so the PreChecked -> SentUnacked edge is validated.
import chronos
import results
import ../../../src/typestates

type
  Message = object
    payload: string

  PreChecked = distinct Message
  SentUnacked = distinct Message

  SendError = enum
    seNetwork
    seTimeout

typestate Message:
  consumeOnTransition = false
  strictTransitions = false
  states PreChecked, SentUnacked
  transitions:
    PreChecked -> SentUnacked

proc send(
    p: PreChecked
): Future[Result[SentUnacked, SendError]] {.async, transition.} =
  return ok(SentUnacked(Message(p)))

let p = PreChecked(Message(payload: "hi"))
let r = waitFor p.send()
doAssert r.isOk
doAssert r.get is SentUnacked
echo "c2_future_result test passed"
