## Test that parenthesized branching syntax works.
##
## Both syntaxes should work:
## - Old: A -> B | C as Result
## - New: A -> (B | C) as Result

import ../src/typestates

type
  Flow = object
  Start = distinct Flow
  Success = distinct Flow
  Failure = distinct Flow
  Done = distinct Flow

typestate Flow:
  consumeOnTransition = false
  states Start, Success, Failure, Done
  transitions:
    # New parenthesized syntax
    Start -> (Success | Failure) as StartResult
    Success -> Done
    Failure -> Done

proc begin(f: Start): StartResult {.transition.} =
  if true:
    toStartResult Success(Flow())
  else:
    toStartResult Failure(Flow())

proc finish(f: Success): Done {.transition.} =
  Done(Flow())

proc finish(f: Failure): Done {.transition.} =
  Done(Flow())

# Test it works
let start = Start(Flow())
let result = start.begin()

case result.kind
of sSuccess:
  echo "Success path"
  discard result.success.finish()
of sFailure:
  echo "Failure path"
  discard result.failure.finish()

echo "Parenthesized syntax test passed!"
