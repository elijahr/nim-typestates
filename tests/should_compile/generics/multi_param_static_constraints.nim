## Test: Multi-param typestate with TWO static constraints of distinct kinds.
##
## This is the nim-debra PinnedScopeContext shape: `[MT: static int, CC: static MyEnum]`.
## Exercises constraint inference loop (typestates.nim §80-111) on the
## "two static params, different inner types" case — the loop must emit
## `[MT: static int, CC: static MyEnum]`, not collapse or swap constraints.
##
## Why it matters: nim-debra 0.8.0's PinnedScopeContext typestate uses this
## exact shape with `[MaxThreads: static int, ConsumerCount: static SomeEnum]`.
## If the inference loop only handles the single-static-param case (as in
## codegen_bug_clean.nim), this fixture surfaces the gap.
import ../../../src/typestates

type
  Mode = enum
    mRead
    mWrite
    mExec

  Ctx[MT: static int, CC: static Mode] = object
    threads: int

  Init[MT: static int, CC: static Mode] = distinct Ctx[MT, CC]
  Active[MT: static int, CC: static Mode] = distinct Ctx[MT, CC]

typestate Ctx[MT: static int, CC: static Mode]:
  consumeOnTransition = false
  strictTransitions = false
  states Init[MT, CC], Active[MT, CC]
  transitions:
    Init[MT, CC] -> Active[MT, CC]

proc activate[MT: static int, CC: static Mode](
    i: Init[MT, CC]
): Active[MT, CC] {.transition.} =
  Active[MT, CC](Ctx[MT, CC](threads: MT))

# Two distinct (MT, CC) pairings to ensure the constrained-params path
# materializes both bindings correctly.
let i1 = Init[4, mRead](Ctx[4, mRead](threads: 0))
let a1 = i1.activate()
doAssert Ctx[4, mRead](a1).threads == 4

let i2 = Init[8, mWrite](Ctx[8, mWrite](threads: 0))
let a2 = i2.activate()
doAssert Ctx[8, mWrite](a2).threads == 8

echo "multi_param_static_constraints test passed"
