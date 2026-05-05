## Layer 1 of the `match_external_consumer` regression test.
##
## Declares the typestate (and therefore the generated kind enum + `match`
## macro). Mirrors `lockfreequeues/typestates/mpmc_push.nim`: kind enum lives
## here, alongside the typestate.
import ../../src/typestates

type
  Payload* = object
    body*: string

  Pending* = distinct Payload
  Ok* = distinct Payload
  Err* = distinct Payload

typestate Payload:
  states Pending, Ok, Err
  transitions:
    Pending -> (Ok | Err) as Outcome

proc decide*(p: sink Pending): Outcome {.transition.} =
  if Payload(p).body == "yes":
    Outcome(kind: oOk, ok: Ok(Payload(p)))
  else:
    Outcome(kind: oErr, err: Err(Payload(p)))
