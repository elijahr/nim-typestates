## AST-verify fixture (GROUP A): a GENERIC typestate whose states are
## `Stage1[T]` / `Stage2[T]`. A proc takes a generic instantiation param
## `s: Stage1[T]` and is marked via a COMBINED pragma block
## `{.raises: [], notATransition.}`.
##
## Correct (AST) result: NO finding — the param resolves to a typestate state
## and the proc is marked notATransition.
##
## Old text scanner: FALSE-FLAGS this. Its single-param string split DOES
## recover `Stage1[T]` as the param type (it is a member of the generic
## `states` list), but it cannot see `notATransition` inside the combined
## `{.raises: [], notATransition.}` block, so it emits a spurious
## `fcUnmarkedProcStrict` error.
import ../../../src/typestates

type
  Pipeline[T] = object
    payload: T

  Stage1[T] = distinct Pipeline[T]
  Stage2[T] = distinct Pipeline[T]

typestate Pipeline[T]:
  consumeOnTransition = false
  states Stage1[T], Stage2[T]
  transitions:
    Stage1[T] -> Stage2[T]

proc probe[T](s: Stage1[T]): int {.raises: [], notATransition.} =
  result = 0
