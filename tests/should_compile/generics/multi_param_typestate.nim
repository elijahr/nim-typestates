## Test: Generic typestate with multiple unconstrained type parameters [T1, T2].
##
## Distinct from the existing multi_param.nim fixture, which uses [K, V]
## with the same usage shape. This fixture intentionally instantiates with
## three different concrete (T1, T2) pairings to exercise the constraint
## inference loop (typestates.nim §80-111) on the multi-param-no-constraint
## branch (`p.kind == nnkIdent`, `c.kind == "none"`).
##
## Bug-class: regression guard for the unconstrained multi-param path.
import ../../../src/typestates

type
  Cell[T1, T2] = object
    a: T1
    b: T2

  Fresh[T1, T2] = distinct Cell[T1, T2]
  HasA[T1, T2] = distinct Cell[T1, T2]
  HasBoth[T1, T2] = distinct Cell[T1, T2]

typestate Cell[T1, T2]:
  consumeOnTransition = false
  strictTransitions = false
  states Fresh[T1, T2], HasA[T1, T2], HasBoth[T1, T2]
  transitions:
    Fresh[T1, T2] -> HasA[T1, T2]
    HasA[T1, T2] -> HasBoth[T1, T2]

proc setA[T1, T2](c: Fresh[T1, T2], a: T1): HasA[T1, T2] {.transition.} =
  var cell = Cell[T1, T2](c)
  cell.a = a
  HasA[T1, T2](cell)

proc setB[T1, T2](c: HasA[T1, T2], b: T2): HasBoth[T1, T2] {.transition.} =
  var cell = Cell[T1, T2](c)
  cell.b = b
  HasBoth[T1, T2](cell)

# Pairing 1: (int, string)
let c1 = Fresh[int, string](Cell[int, string]())
let c1a = c1.setA(1)
let c1b = c1a.setB("one")
doAssert Cell[int, string](c1b).a == 1
doAssert Cell[int, string](c1b).b == "one"

# Pairing 2: (string, float)
let c2 = Fresh[string, float](Cell[string, float]())
let c2a = c2.setA("pi")
let c2b = c2a.setB(3.14)
doAssert Cell[string, float](c2b).a == "pi"
doAssert Cell[string, float](c2b).b == 3.14

# Pairing 3: (float, int) — distinct from pairing 1
let c3 = Fresh[float, int](Cell[float, int]())
let c3a = c3.setA(2.71)
let c3b = c3a.setB(42)
doAssert Cell[float, int](c3b).a == 2.71
doAssert Cell[float, int](c3b).b == 42

echo "multi_param_typestate test passed"
