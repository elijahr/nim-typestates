## Single-target match invoked from a generic proc body.
## Parallels match_generic_call_site.nim: verifies that arm-head sym /
## openSymChoice resolution accepts the generic-context node kinds the
## helper sees after sema runs over the surrounding generic body.
import ../../../src/typestates

type
  Box = object
    v: string
  Empty = distinct Box
  Full = distinct Box

typestate Box:
  states Empty, Full
  transitions:
    Empty -> Full

proc fill(e: sink Empty, s: string): Full {.transition.} =
  Full(Box(v: s))

proc useFull[T](e: sink Empty, payload: T): T =
  let f = e.fill($payload)
  var outVal: T
  match f:
    Full(x):
      doAssert Box(x).v == $payload
      outVal = payload
  outVal

doAssert useFull[int](Empty(Box()), 42) == 42
doAssert useFull[string](Empty(Box()), "hello") == "hello"
echo "match_single_target_generic test passed"
