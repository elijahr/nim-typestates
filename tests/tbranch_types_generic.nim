## Test that generic branch type names are accepted by the parser.
## Note: Full codegen for generic typestates is not yet implemented,
## so this test only verifies parsing works.

import ../src/typestates

type
  Container[T] = object
    value: T
  Empty[T] = distinct Container[T]
  Full[T] = distinct Container[T]
  Error[T] = distinct Container[T]

# This should parse without error - the 'as FillResult[T]' syntax is accepted
typestate Container[T]:
  states Empty[T], Full[T], Error[T]
  transitions:
    Empty[T] -> Full[T] | Error[T] as FillResult[T]

echo "Generic branch type parsing test passed"
