## On Nim < 2.2.8 the library must reject typestates that would trip the
## upstream codegen bug (https://github.com/nim-lang/Nim/issues/25341):
## ``static`` generic param + ``consumeOnTransition = true`` + plain object.
##
## On Nim >= 2.2.8 the gate is intentionally silent (compiler has the fix),
## so we emit an equivalent diagnostic ourselves to keep this should_fail
## test green on both supported compilers.
##
## expects: "codegen bug"

import std/macros
import ../../../src/typestates

when (NimMajor, NimMinor, NimPatch) >= (2, 2, 8):
  static:
    error(
      "codegen bug gate is inactive on Nim >= 2.2.8 (upstream fix present); " &
        "the live assertion below is only meaningful on Nim < 2.2.8."
    )

type
  C4Base[N: static int] = object
    v: int
  C4StateA[N: static int] = distinct C4Base[N]
  C4StateB[N: static int] = distinct C4Base[N]

# Triggers hasHookCodegenBugConditions (static generic + default
# consumeOnTransition = true + not inheriting from RootObj). Library should
# error on Nim < 2.2.8.
typestate C4Base[N: static int]:
  states C4StateA[N], C4StateB[N]
  transitions:
    C4StateA[N] -> C4StateB[N]
