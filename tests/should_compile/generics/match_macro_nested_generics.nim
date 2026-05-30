## D1 regression — variant 3/4: nested generics (generic proc -> generic typestate).
##
## Multi-level binding: the typestate is itself generic [T], AND it is
## invoked from a generic proc body [U]. When sema resolves the arm head
## under TWO layers of generic binding, the node kind that reaches
## `buildMatchCase` may be `nnkSym`, `nnkOpenSymChoice`, or a bracket
## expression — all three must be accepted.
##
## Bug-class: the v0.7.0 bug was about single-level arm-head resolution.
## Nested generics stress the same code path with a deeper binding stack.
import ../../../src/typestates

type
  Maybe[T] = object
    v: T

  Empty[T] = distinct Maybe[T]
  Filled[T] = distinct Maybe[T]
  Drained[T] = distinct Maybe[T]
  Captured[T] = distinct Maybe[T]

typestate Maybe[T]:
  consumeOnTransition = false
  strictTransitions = false
  states Empty[T], Filled[T], Drained[T], Captured[T]
  transitions:
    Empty[T] -> Filled[T]
    Filled[T] -> (Drained[T] | Captured[T]) as Resolved[T]

proc fill[T](e: sink Empty[T], val: T): Filled[T] {.transition.} =
  Filled[T](Maybe[T](v: val))

proc resolve[T](f: sink Filled[T], drain: bool): Resolved[T] {.transition.} =
  if drain:
    Resolved[T](kind: rDrained, drained: Drained[T](Maybe[T](f)))
  else:
    Resolved[T](kind: rCaptured, captured: Captured[T](Maybe[T](f)))

# Generic proc [U] invoking match on a typestate that is itself [T].
# Instantiation closes both layers: the arm-head Drained[T] / Captured[T]
# must remain a valid match arm under that double binding.
proc useMaybe[T](val: T, drain: bool): string =
  let e = Empty[T](Maybe[T]())
  let f = e.fill(val)
  # match emits `move(r.<field>)` on the discriminator — `r` must be `var`.
  var r = f.resolve(drain)
  var label: string
  match r:
    Drained(d):
      doAssert Maybe[T](d).v == val
      label = "drained"
    Captured(c):
      doAssert Maybe[T](c).v == val
      label = "captured"
  label

doAssert useMaybe[int](42, true) == "drained"
doAssert useMaybe[int](42, false) == "captured"
doAssert useMaybe[string]("hi", true) == "drained"
doAssert useMaybe[string]("hi", false) == "captured"
echo "match_macro_nested_generics test passed"
