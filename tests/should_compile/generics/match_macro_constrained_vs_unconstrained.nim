## D1 regression — variant 4/4: constrained vs unconstrained generic params.
##
## The v0.7.0 bug-class was about node-kind handling in `buildMatchCase`.
## A subtler manifestation: when an arm-head node refers to a state whose
## generic params include a TYPECLASS constraint (`T: SomeInteger`) versus
## an UNCONSTRAINED `T`, sema may produce different bracket-expr shapes
## for the arm head. Both must be accepted by the match macro.
##
## This fixture defines TWO parallel typestates — one with an unconstrained
## param and one with a typeclass-constrained param — and exercises match
## arms over both from a generic call site. If only one shape is accepted,
## this fixture surfaces the asymmetry.
import ../../../src/typestates

# --- Typestate A: unconstrained param ----------------------------------------
type
  BoxA[T] = object
    v: T

  EmptyA[T] = distinct BoxA[T]
  FilledA[T] = distinct BoxA[T]
  PrunedA[T] = distinct BoxA[T]
  KeptA[T] = distinct BoxA[T]

typestate BoxA[T]:
  consumeOnTransition = false
  strictTransitions = false
  states EmptyA[T], FilledA[T], PrunedA[T], KeptA[T]
  transitions:
    EmptyA[T] -> FilledA[T]
    FilledA[T] -> (PrunedA[T] | KeptA[T]) as DecisionA[T]

proc fillA[T](e: sink EmptyA[T], v: T): FilledA[T] {.transition.} =
  FilledA[T](BoxA[T](v: v))

proc decideA[T](f: sink FilledA[T], keep: bool): DecisionA[T] {.transition.} =
  if keep:
    DecisionA[T](kind: dKeptA, keptA: KeptA[T](BoxA[T](f)))
  else:
    DecisionA[T](kind: dPrunedA, prunedA: PrunedA[T](BoxA[T](f)))

# --- Typestate B: typeclass-constrained param --------------------------------
type
  BoxB[T: SomeInteger] = object
    v: T

  EmptyB[T: SomeInteger] = distinct BoxB[T]
  FilledB[T: SomeInteger] = distinct BoxB[T]
  PrunedB[T: SomeInteger] = distinct BoxB[T]
  KeptB[T: SomeInteger] = distinct BoxB[T]

typestate BoxB[T: SomeInteger]:
  consumeOnTransition = false
  strictTransitions = false
  states EmptyB[T], FilledB[T], PrunedB[T], KeptB[T]
  transitions:
    EmptyB[T] -> FilledB[T]
    FilledB[T] -> (PrunedB[T] | KeptB[T]) as DecisionB[T]

proc fillB[T: SomeInteger](e: sink EmptyB[T], v: T): FilledB[T] {.transition.} =
  FilledB[T](BoxB[T](v: v))

proc decideB[T: SomeInteger](
    f: sink FilledB[T], keep: bool
): DecisionB[T] {.transition.} =
  if keep:
    DecisionB[T](kind: dKeptB, keptB: KeptB[T](BoxB[T](f)))
  else:
    DecisionB[T](kind: dPrunedB, prunedB: PrunedB[T](BoxB[T](f)))

# --- Cross-shape generic call site ------------------------------------------
proc roundTripA[T](v: T, keep: bool): string =
  let e = EmptyA[T](BoxA[T]())
  let f = e.fillA(v)
  # match emits `move(d.<field>)` on the discriminator — `d` must be `var`.
  var d = f.decideA(keep)
  var label: string
  match d:
    PrunedA(p):
      doAssert BoxA[T](p).v == v
      label = "pruned"
    KeptA(k):
      doAssert BoxA[T](k).v == v
      label = "kept"
  label

proc roundTripB[T: SomeInteger](v: T, keep: bool): string =
  let e = EmptyB[T](BoxB[T]())
  let f = e.fillB(v)
  var d = f.decideB(keep)
  var label: string
  match d:
    PrunedB(p):
      doAssert BoxB[T](p).v == v
      label = "pruned"
    KeptB(k):
      doAssert BoxB[T](k).v == v
      label = "kept"
  label

# Unconstrained: string is fine
doAssert roundTripA[string]("hi", true) == "kept"
doAssert roundTripA[int](7, false) == "pruned"

# Constrained: must be an integer
doAssert roundTripB[int](7, true) == "kept"
doAssert roundTripB[uint32](9'u32, false) == "pruned"

echo "match_macro_constrained_vs_unconstrained test passed"
