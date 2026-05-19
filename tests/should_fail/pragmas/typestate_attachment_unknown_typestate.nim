## Test (TA-001 surrogate): pragma references a typestate name that was
## never declared.
##
## Because the typestate-attachment pragma is emitted per-typestate (i.e.
## the `typestate Foo:` macro is what generates the `Foo` pragma macro),
## an undeclared typestate name surfaces as Nim's own "undeclared
## identifier" error attributed to the pragma site, NOT as the TA-001
## message literal from Doc A §3.7. The end effect — a compile-time
## error pinned to the offending `{.NotDeclared: Whatever.}` — matches
## the intent of TA-001.
##
## This fixture asserts the Nim error fires (any compile failure is OK)
## and that the offending identifier name appears in the diagnostic so
## the user knows which pragma name was unresolved.
# expects: "NeverDeclaredTypestate"
import ../../../src/typestates

type Foo {.NeverDeclaredTypestate: SomeState.} = object
  x: int
