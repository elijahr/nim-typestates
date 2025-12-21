## Test: Wildcard bridge (* -> Target.State)
import ../../../src/typestates

type
  App = object
  Running = distinct App
  Paused = distinct App
  Error = distinct App

  Shutdown = object
  Terminal = distinct Shutdown

typestate Shutdown:
  consumeOnTransition = false # Opt out for existing tests
  strictTransitions = false
  states Terminal

typestate App:
  consumeOnTransition = false # Opt out for existing tests
  strictTransitions = false
  states Running, Paused, Error
  transitions:
    Running -> Paused
    Paused -> Running
    Running -> Error
  bridges:
    * ->Shutdown.Terminal # Any state can shutdown

proc pause(a: Running): Paused {.transition.} =
  Paused(a.App)

proc shutdownRunning(a: Running): Terminal {.transition.} =
  Terminal(Shutdown())

proc shutdownPaused(a: Paused): Terminal {.transition.} =
  Terminal(Shutdown())

proc shutdownError(a: Error): Terminal {.transition.} =
  Terminal(Shutdown())

let app = Running(App())
let terminal = app.shutdownRunning()
echo "wildcard_bridge test passed"
