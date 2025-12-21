## Test: Wildcard combined with explicit transitions
import ../../../src/typestates

type
  Process = object
  Running = distinct Process
  Paused = distinct Process
  Stopped = distinct Process

typestate Process:
  consumeOnTransition = false # Opt out for existing tests
  strictTransitions = false
  states Running, Paused, Stopped
  transitions:
    Running -> Paused # Explicit
    Paused -> Running # Explicit
    * ->Stopped # Wildcard: any state can stop

proc pause(p: Running): Paused {.transition.} =
  Paused(p.Process)

proc resume(p: Paused): Running {.transition.} =
  Running(p.Process)

proc stop(p: Running): Stopped {.transition.} =
  Stopped(p.Process)

proc stopPaused(p: Paused): Stopped {.transition.} =
  Stopped(p.Process)

let p = Running(Process())
let paused = p.pause()
let resumed = paused.resume()
let stopped = resumed.stop()
echo "wildcard_and_explicit test passed"
