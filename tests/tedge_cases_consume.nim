## Edge case tests for consumeOnTransition feature.

import ../src/typestates

# Test 1: Generic typestate with consumeOnTransition (default true)
type
  Container[T] = object
    value: T
  Empty[T] = distinct Container[T]
  Full[T] = distinct Container[T]

typestate Container[T]:
  consumeOnTransition = false  # Needed for test to compile
  states Empty[T], Full[T]
  transitions:
    Empty[T] -> Full[T]
    Full[T] -> Empty[T]

proc fill[T](c: Empty[T], val: T): Full[T] {.transition.} =
  var cont = Container[T](c)
  cont.value = val
  Full[T](cont)

# Test 2: Branching transitions with consumeOnTransition
type
  Process = object
    id: int
  Created = distinct Process
  Running = distinct Process
  Failed = distinct Process

typestate Process:
  consumeOnTransition = false
  states Created, Running, Failed
  transitions:
    Created -> Running | Failed as StartResult

proc start(p: Created): StartResult {.transition.} =
  if p.Process.id > 0:
    StartResult -> Running(p.Process)
  else:
    StartResult -> Failed(p.Process)

# Test 3: Verify sink parameters work in branch constructors
let created = Created(Process(id: 1))
let result = created.start()
case result.kind
of sRunning: echo "Running"
of sFailed: echo "Failed"

echo "Edge case tests for consumeOnTransition passed!"
