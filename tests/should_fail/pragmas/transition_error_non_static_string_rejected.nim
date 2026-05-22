## Test (v0.9.3 transitionError): when the `transitionError:` rhs is NOT
## a static string literal (e.g., a runtime `var`), the extractor must
## reject the declaration at compile time with the canonical message:
## `transitionError must be a static string literal (no concatenation,
## no fmt)`.
##
## The pragma template declares `msg: static string`, so Nim's typechecker
## would also reject most non-literal forms — but this test pins the
## explicit, intentional diagnostic from `extractTransitionErrorPragma`.
# expects: "transitionError must be a static string literal"
import ../../../src/typestates

type
  GadgetT = object
  GadgetIdle = distinct GadgetT
  GadgetReady = distinct GadgetT
  GadgetDone = distinct GadgetT

typestate GadgetT:
  states GadgetIdle, GadgetReady, GadgetDone
  initial: GadgetIdle
  terminal: GadgetDone
  transitions:
    GadgetIdle -> GadgetReady
    GadgetReady -> GadgetDone

var someRuntimeString = "dynamic message"

# `someRuntimeString` is a runtime `var`, not a string literal.
# `extractTransitionErrorPragma` must fire its canonical error.
proc ready(g: GadgetIdle): GadgetReady
    {.transition, transitionError: someRuntimeString.} =
  GadgetReady(g)
