## Test generic branch types for branching transitions.

import std/unittest
import ../src/typestates

type
  Container[T] = object
    value: T
  Empty[T] = distinct Container[T]
  Full[T] = distinct Container[T]
  Error[T] = distinct Container[T]

typestate Container[T]:
  consumeOnTransition = false  # Opt out for this test to allow reusing states
  states Empty[T], Full[T], Error[T]
  transitions:
    Empty[T] -> (Full[T] | Error[T]) as FillResult[T]
    Full[T] -> Empty[T]

suite "Generic Branch Types - Single Param":
  test "ContainerState enum exists":
    check fsEmpty is ContainerState
    check fsFull is ContainerState
    check fsError is ContainerState

  test "ContainerStates union type works":
    proc acceptAny[T](c: ContainerStates[T]): ContainerState =
      c.state

    let e = Empty[int](Container[int](value: 0))
    check acceptAny(e) == fsEmpty

  test "state procs work with generics":
    let e = Empty[int](Container[int](value: 0))
    let f = Full[string](Container[string](value: "hello"))

    check e.state == fsEmpty
    check f.state == fsFull

  test "FillResultKind enum exists":
    check fFull is FillResultKind
    check fError is FillResultKind

  test "FillResult[T] type exists and is constructible":
    let b1 = FillResult[int](kind: fFull, full: Full[int](Container[int](value: 42)))
    check b1.kind == fFull
    check Container[int](b1.full).value == 42

  test "toFillResult constructors work":
    let full = Full[int](Container[int](value: 100))
    let error = Error[int](Container[int](value: 0))

    let b1 = toFillResult(full)
    check b1.kind == fFull
    check Container[int](b1.full).value == 100

    let b2 = toFillResult(error)
    check b2.kind == fError

  test "-> operator works with generics":
    let full = Full[int](Container[int](value: 100))

    let b1 = FillResult[int] -> full
    check b1.kind == fFull
    check Container[int](b1.full).value == 100

  test "branching transition proc with generics":
    # Note: {.transition.} pragma validation for generics is a separate feature
    # This test verifies the generated types work correctly in generic procs
    proc fill[T](e: Empty[T], val: T): FillResult[T] =
      if val == default(T):
        FillResult[T] -> Error[T](Container[T](e))
      else:
        var c = Container[T](e)
        c.value = val
        FillResult[T] -> Full[T](c)

    let empty = Empty[int](Container[int](value: 0))

    let result1 = fill(empty, 42)
    check result1.kind == fFull
    check Container[int](result1.full).value == 42

    let result2 = fill(empty, 0)
    check result2.kind == fError
