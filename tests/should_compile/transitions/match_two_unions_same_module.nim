## F4: two branching unions in the same module both use `match`.
## Verifies Nim disambiguates `match` macros by typed first parameter.
import ../../../src/typestates

type
  Box = object
    n: int

  Empty = distinct Box
  Filling = distinct Box
  Full = distinct Box
  Errored = distinct Box

typestate Box:
  states Empty, Filling, Full, Errored
  transitions:
    Empty -> (Filling | Errored) as StartResult
    Filling -> (Full | Errored) as FinishResult

proc start(b: sink Empty): StartResult {.transition.} =
  StartResult(kind: sFilling, filling: Filling(Box(b)))

proc finish(b: sink Filling): FinishResult {.transition.} =
  FinishResult(kind: fFull, full: Full(Box(b)))

var r1 = Empty(Box(n: 1)).start()
var s1 = ""
match r1:
  Filling(f):
    s1 = "Filling"
  Errored(e):
    s1 = "Errored"
doAssert s1 == "Filling"

# Reconstruct a Filling for the second match (since r1 was consumed).
var r2 = Filling(Box(n: 2)).finish()
var s2 = ""
match r2:
  Full(fv):
    s2 = "Full"
  Errored(ev):
    s2 = "Errored"
doAssert s2 == "Full"

echo "match_two_unions_same_module test passed"
