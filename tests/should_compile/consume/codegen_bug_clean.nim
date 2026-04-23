## On Nim >= 2.2.8 (where issue #25341 is fixed) the library must NOT
## reject the same typestate shape that the gate rejects on Nim < 2.2.8:
## static generic param + ``consumeOnTransition = true`` + plain object.
##
## On Nim < 2.2.8 the test stubs out the typestate declaration and prints
## a skip notice so the runner records a pass without exercising the
## known-bad path.

import ../../../src/typestates

when (NimMajor, NimMinor, NimPatch) < (2, 2, 8):
  echo "skipped: requires Nim >= 2.2.8 (codegen bug fix for #25341)"
else:
  type
    C4Base[N: static int] = object
      v: int
    C4StateA[N: static int] = distinct C4Base[N]
    C4StateB[N: static int] = distinct C4Base[N]

  typestate C4Base[N: static int]:
    states C4StateA[N], C4StateB[N]
    transitions:
      C4StateA[N] -> C4StateB[N]

  proc advance[N: static int](a: sink C4StateA[N]): C4StateB[N] {.transition.} =
    C4StateB[N](C4Base[N](a))

  let b = advance(C4StateA[4](C4Base[4](v: 1)))
  echo "compiled and ran on Nim >= 2.2.8: ", C4Base[4](b).v
