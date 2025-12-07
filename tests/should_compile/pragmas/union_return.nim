## Test: Union return type for branching transitions
import ../../../src/typestates

type
  Request = object
    valid: bool
  Pending = distinct Request
  Success = distinct Request
  Failure = distinct Request

typestate Request:
  consumeOnTransition = false  # Opt out for existing tests
  strictTransitions = false
  states Pending, Success, Failure
  transitions:
    Pending -> (Success | Failure) as ProcessResult

# Define separate procs for each branch - the transition pragma validates both paths
proc processSuccess(r: Pending): Success {.transition.} =
  Success(r.Request)

proc processFailure(r: Pending): Failure {.transition.} =
  Failure(r.Request)

# Test that both transition directions compile and validate
let validReq = Pending(Request(valid: true))
let success = validReq.processSuccess()
doAssert success is Success

let invalidReq = Pending(Request(valid: false))
let failure = invalidReq.processFailure()
doAssert failure is Failure

echo "union_return test passed"
