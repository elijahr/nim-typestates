## Test (CFG-001 negative — module-qualified generic transition call,
## round-13 BOT-C2, verify.nim:extractCalleeName): an end-to-end
## compile-and-run check that a registered generic transition invoked
## through a module qualifier (`module.foo[T](args)`) is accepted by
## the CFG analyzer and emits running code.
##
## The pre/post-fix discriminator for `extractCalleeName`'s
## `nnkBracketExpr` branch lives in `tests/textract_callee_name.nim`,
## which drives the recognizer directly with hand-built ASTs across
## every head shape the analyzer encounters (bare-ident, sym-choice,
## bare generic, module-qualified, module-qualified generic). The
## structural test is necessary because generic typestates are
## deferred in 0.9.0 (verify.nim:2120) — the CFG walk skips bodies
## that involve generic state types, so an end-to-end fixture
## cannot reliably surface a `CFG-001` diagnostic difference between
## the pre-fix and post-fix recognizer.
##
## This fixture is the complementary end-to-end check: a generic
## typestate `Box[T]`, a generic transition `unseal[T]`, and a
## registered caller `unsealHere[T]` that drives the
## `module.unseal[T](b)` call shape. Pre- and post-fix this fixture
## compiles cleanly (deferred generic-typestate CFG walk masks the
## recognizer effect); the fixture pins the runtime behaviour so a
## future un-deferral of generic-typestate CFG walks will not regress.
##
## Audit-matrix extension over r3/r5/r8/r9/r12 — each prior round
## closed a distinct callee head-shape class (bare-ident, dot-call,
## transparent wrappers, sink-overload, multi-typestate-param). r13
## closes the dot-then-bracket cross-module generic shape.
import ../../../src/typestates

type
  Box[T] = object
    item: T

  Sealed[T] = distinct Box[T]
  Opened[T] = distinct Box[T]

typestate Box[T]:
  consumeOnTransition = false
  strictTransitions = false
  states Sealed[T], Opened[T]
  initial:
    Sealed[T]
  terminal:
    Opened[T]
  transitions:
    Sealed[T] -> Opened[T]

proc unseal[T](b: sink Sealed[T]): Opened[T] {.transition.} =
  ## Generic transition target of the module-qualified call below.
  Opened[T](Box[T](b))

proc unsealHere[T](b: sink Sealed[T]): Opened[T] {.transition.} =
  ## Registered caller. The body's sole effect is a module-qualified
  ## explicit-T sink-consume of `b` against the in-module `unseal`
  ## transition. The module qualifier is the unsuffixed file name,
  ## which Nim accepts for in-module qualified references; the
  ## resulting AST mirrors cross-module calls exactly — the analyzer
  ## cannot distinguish in-module from cross-module qualification.
  result = cfg_analyzer_module_qualified_generic_call.unseal[T](b)

verifyTypestates()
let b0 = Sealed[int](Box[int](item: 7))
discard unsealHere[int](b0)
echo "cfg_analyzer_module_qualified_generic_call ok"
