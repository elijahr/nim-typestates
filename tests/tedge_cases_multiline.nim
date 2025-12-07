## Edge case tests for multiline state list syntax.

import ../src/typestates

# Test 1: Generic types in multiline format
type
  Box[T] = object
    value: T
  Sealed[T] = distinct Box[T]
  Opened[T] = distinct Box[T]

typestate Box[T]:
  consumeOnTransition = false
  states:
    Sealed[T]
    Opened[T]
  transitions:
    Sealed[T] -> Opened[T]
    Opened[T] -> Sealed[T]

proc open[T](b: Sealed[T]): Opened[T] {.transition.} = Opened[T](Box[T](b))
proc close[T](b: Opened[T]): Sealed[T] {.transition.} = Sealed[T](Box[T](b))

# Test 2: Multiline with initial/terminal blocks
type
  Workflow = object
  Draft = distinct Workflow
  Review = distinct Workflow
  Approved = distinct Workflow
  Rejected = distinct Workflow

typestate Workflow:
  consumeOnTransition = false
  states:
    Draft
    Review
    Approved
    Rejected
  initial: Draft
  terminal: Approved
  transitions:
    Draft -> Review
    Review -> Approved
    Review -> Rejected

proc submit(d: Draft): Review {.transition.} = Review(Workflow())
proc approve(r: Review): Approved {.transition.} = Approved(Workflow())
proc reject(r: Review): Rejected {.transition.} = Rejected(Workflow())

# Test 3: Multiline states with branching transitions
type
  Request = object
  Pending = distinct Request
  Success = distinct Request
  Error = distinct Request

typestate Request:
  consumeOnTransition = false
  states:
    Pending
    Success
    Error
  transitions:
    Pending -> Success | Error as RequestResult

proc execute(p: Pending): RequestResult {.transition.} =
  RequestResult -> Success(Request())

echo "Edge case tests for multiline states passed!"
