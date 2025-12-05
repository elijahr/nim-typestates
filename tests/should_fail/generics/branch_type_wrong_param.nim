## Test: Branch type with wrong param name should fail
## Expected error: undeclared identifier: 'T'
##
## When branch type uses K instead of T, and states use T,
## the generated code fails because T is not in scope for
## the state type lookups.

import ../../../src/typestates

type
  Container[T] = object
    value: T
  Empty[T] = distinct Container[T]
  Full[T] = distinct Container[T]
  Error[T] = distinct Container[T]

# Branch type uses K but states use T
typestate Container[T]:
  states Empty[T], Full[T], Error[T]
  transitions:
    Empty[T] -> Full[T] | Error[T] as FillResult[K]  # K instead of T!
