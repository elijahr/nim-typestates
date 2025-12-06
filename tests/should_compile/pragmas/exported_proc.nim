## Test: Exported transition proc with visibility marker
import ../../../src/typestates

type
  Counter = object
    value: int
  Zero = distinct Counter
  NonZero = distinct Counter

typestate Counter:
  consumeOnTransition = false  # Opt out for existing tests
  strictTransitions = false
  states Zero, NonZero
  transitions:
    Zero -> NonZero
    NonZero -> Zero

proc increment*(c: Zero): NonZero {.transition.} =
  var counter = c.Counter
  counter.value = 1
  NonZero(counter)

proc reset*(c: NonZero): Zero {.transition.} =
  Zero(Counter(value: 0))

let z = Zero(Counter(value: 0))
let nz = z.increment()
doAssert nz.Counter.value == 1
let z2 = nz.reset()
doAssert z2.Counter.value == 0
echo "exported_proc test passed"
