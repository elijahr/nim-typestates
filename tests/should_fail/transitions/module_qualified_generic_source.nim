## Test: `{.transition.}` with a module-qualified generic source
## (`helper.StateA[int]`) must produce a CLEAN diagnostic — not a
## compile-time crash — when the transition is defined outside the
## typestate's declaring module.
##
## Regression bar: extractTypeName on an nnkBracketExpr used to do
## `node[0].strVal` unconditionally, so a DotExpr head crashed the
## macro before the "same-module" check could report the real
## problem. The fix delegates the head to `extractTypeName` itself,
## which handles DotExpr via `node.repr`.
##
## What we assert: the compiler output mentions the external-module
## rule, proving the macro got past the extract step and reached the
## diagnostic.
# expects: "from external module"
import ../../../src/typestates
import ../../helpers/typestate_generic_helper

proc advance(s: typestate_generic_helper.StateA[int]): StateB[int] {.transition.} =
  StateB[int](Cell[int](s))
