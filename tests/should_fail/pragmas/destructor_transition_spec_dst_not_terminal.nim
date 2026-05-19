## Test (DT-011): two-arg destructorTransition where the spec DstState is
## NOT a declared terminal of the typestate.
## Expected error: "is not a terminal state of typestate"
# expects: "is not a terminal state of typestate"
import ../../../src/typestates

type
  Job = object
  Queued = distinct Job
  Running = distinct Job
  Finished = distinct Job

typestate Job:
  consumeOnTransition = false
  strictTransitions = false
  states Queued, Running, Finished
  initial:
    Queued
  terminal:
    Finished
  transitions:
    Queued -> Running
    Running -> Finished

# Wrong: Running is NOT a terminal state; the destructor on Queued cannot
# pin Running as its terminal destination.
proc `=destroy`(q: var Queued) {.destructorTransition: Queued -> Running.} =
  discard
