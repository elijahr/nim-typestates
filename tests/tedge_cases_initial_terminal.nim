## Edge case tests for initial/terminal state declarations.

import ../src/typestates

# Test 1: Single initial state
type
  SimpleFlow = object
  Start = distinct SimpleFlow
  Middle = distinct SimpleFlow
  End = distinct SimpleFlow

typestate SimpleFlow:
  consumeOnTransition = false
  states Start, Middle, End
  initial: Start
  terminal: End
  transitions:
    Start -> Middle
    Middle -> End

proc beginFlow(s: Start): Middle {.transition.} = Middle(SimpleFlow())
proc finishFlow(m: Middle): End {.transition.} = End(SimpleFlow())

# Test 2: Separate initial and terminal
type
  MultiTerm = object
  Begin = distinct MultiTerm
  Success = distinct MultiTerm
  Failure = distinct MultiTerm

typestate MultiTerm:
  consumeOnTransition = false
  states Begin, Success, Failure
  initial: Begin
  terminal: Success
  transitions:
    Begin -> Success
    Begin -> Failure

proc succeed(b: Begin): Success {.transition.} = Success(MultiTerm())
proc fail(b: Begin): Failure {.transition.} = Failure(MultiTerm())

# Test 3: Generic typestate with initial/terminal
type
  Pipeline[T] = object
    data: T
  Pending[T] = distinct Pipeline[T]
  Processing[T] = distinct Pipeline[T]
  Done[T] = distinct Pipeline[T]

typestate Pipeline[T]:
  consumeOnTransition = false
  states Pending[T], Processing[T], Done[T]
  initial: Pending[T]
  terminal: Done[T]
  transitions:
    Pending[T] -> Processing[T]
    Processing[T] -> Done[T]

proc beginProcessing[T](p: Pending[T]): Processing[T] {.transition.} =
  Processing[T](Pipeline[T](p))

proc complete[T](p: Processing[T]): Done[T] {.transition.} =
  Done[T](Pipeline[T](p))

# Test 4: Wildcard with terminal (wildcard TO terminal is valid)
type
  Resettable = object
  Active = distinct Resettable
  Paused = distinct Resettable
  Stopped = distinct Resettable

typestate Resettable:
  consumeOnTransition = false
  states Active, Paused, Stopped
  terminal: Stopped
  transitions:
    Active -> Paused
    Paused -> Active
    * -> Stopped  # Any state can transition TO Stopped (terminal)

proc pause(a: Active): Paused {.transition.} = Paused(Resettable())
proc resume(p: Paused): Active {.transition.} = Active(Resettable())
proc stopFromActive(a: Active): Stopped {.transition.} = Stopped(Resettable())
proc stopFromPaused(p: Paused): Stopped {.transition.} = Stopped(Resettable())

echo "Edge case tests for initial/terminal passed!"
