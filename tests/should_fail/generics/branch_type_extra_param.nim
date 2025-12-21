## Test: Branch type with extra undeclared param should fail at usage
## Expected error: cannot instantiate: 'U'
##
## Note: The type definition compiles, but usage fails because U is
## a phantom type parameter that cannot be inferred or bound.

import ../../../src/typestates

type
  Container[T] = object
    value: T

  Empty[T] = distinct Container[T]
  Full[T] = distinct Container[T]
  Error[T] = distinct Container[T]

# Branch type has extra param U that doesn't come from typestate
typestate Container[T]:
  consumeOnTransition = false # Opt out for existing tests
  states Empty[T], Full[T], Error[T]
  transitions:
    Empty[T] -> (Full[T] | Error[T]) as FillResult[T, U] # U is undefined!

# Try to use it - this should fail
let full = Full[int](Container[int](value: 42))
let result = FillResult[int, string] -> full # Error: cannot instantiate U
