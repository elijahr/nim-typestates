## Test: Circular transitions (A -> B -> C -> A)
import ../../../src/typestates

type
  Cycle = object
    count: int
  StateA = distinct Cycle
  StateB = distinct Cycle
  StateC = distinct Cycle

typestate Cycle:
  isSealed = false
  strictTransitions = false
  states StateA, StateB, StateC
  transitions:
    StateA -> StateB
    StateB -> StateC
    StateC -> StateA

proc toB(c: StateA): StateB {.transition.} =
  var cycle = c.Cycle
  inc cycle.count
  StateB(cycle)

proc toC(c: StateB): StateC {.transition.} =
  var cycle = c.Cycle
  inc cycle.count
  StateC(cycle)

proc toA(c: StateC): StateA {.transition.} =
  var cycle = c.Cycle
  inc cycle.count
  StateA(cycle)

var a = StateA(Cycle(count: 0))
let b = a.toB()
let c = b.toC()
a = c.toA()
doAssert a.Cycle.count == 3
echo "circular test passed"
