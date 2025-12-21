## Test generic constraint inference from state types.
##
## Verifies that the typestate macro can automatically infer generic parameter
## constraints from the state type definitions, eliminating the need to
## explicitly specify constraints like `N: static int` in the typestate block.

import ../src/typestates

# Test 1: Basic static int inference
# (typestates must be at module level due to export markers)
type
  Buffer1[N: static int] = object
    data: array[N, int]

  Empty1[N: static int] = distinct Buffer1[N]
  Filled1[N: static int] = distinct Buffer1[N]

# N's constraint is automatically inferred from Empty1/Filled1
typestate Buffer1[N]:
  consumeOnTransition = false
  states Empty1[N], Filled1[N]
  transitions:
    Empty1 -> Filled1
    Filled1 -> Empty1

proc fill1[N: static int](e: Empty1[N]): Filled1[N] {.transition.} =
  var buf = Buffer1[N](e)
  for i in 0 ..< N:
    buf.data[i] = i
  result = Filled1[N](buf)

proc clear1[N: static int](f: Filled1[N]): Empty1[N] {.transition.} =
  result = Empty1[N](Buffer1[N](data: default(array[N, int])))

block test1:
  let empty = Empty1[4](Buffer1[4]())
  let filled = empty.fill1()
  let cleared = filled.clear1()
  echo "Test 1: Static int inference - PASSED"

# Test 2: Verify inference doesn't break already-constrained params
type
  Container2[M: static int] = object
    size: int

  Initial2[M: static int] = distinct Container2[M]
  Final2[M: static int] = distinct Container2[M]

# Explicit constraint still works
typestate Container2[M: static int]:
  consumeOnTransition = false
  states Initial2[M], Final2[M]
  transitions:
    Initial2 -> Final2

proc finish2[M: static int](i: Initial2[M]): Final2[M] {.transition.} =
  result = Final2[M](Container2[M](i))

block test2:
  let init = Initial2[8](Container2[8](size: 8))
  let final = init.finish2()
  echo "Test 2: Explicit constraints still work - PASSED"

# Test 3: Multiple generic parameters with same constraint
type
  Matrix3[R: static int, C: static int] = object
    rows: int
    cols: int

  Uninit3[R: static int, C: static int] = distinct Matrix3[R, C]
  Ready3[R: static int, C: static int] = distinct Matrix3[R, C]

# Both R and C should have their constraints inferred
typestate Matrix3[R, C]:
  consumeOnTransition = false
  states Uninit3[R, C], Ready3[R, C]
  transitions:
    Uninit3 -> Ready3

proc init3[R: static int, C: static int](
    u: Uninit3[R, C]
): Ready3[R, C] {.transition.} =
  result = Ready3[R, C](Matrix3[R, C](rows: R, cols: C))

block test3:
  let uninit = Uninit3[3, 4](Matrix3[3, 4]())
  let ready = uninit.init3()
  echo "Test 3: Multiple generic params - PASSED"

echo "All constraint inference tests passed!"
