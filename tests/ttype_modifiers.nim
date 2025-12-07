## Test that type modifiers work with transition pragma.
##
## Standard Nim type modifiers like sink, var, lent should be
## supported in transition procs.

import ../src/typestates

# =============================================================================
# Test 1: sink parameter
# =============================================================================

type
  Token = object
    id: string
  Valid = distinct Token
  Used = distinct Token

typestate Token:
  consumeOnTransition = false  # For testing, disable copy prevention
  states Valid, Used
  transitions:
    Valid -> Used

proc createToken(id: string): Valid =
  Valid(Token(id: id))

proc consume(token: sink Valid): Used {.transition.} =
  ## Consume the token - sink enforces ownership transfer.
  let id = Token(token).id
  echo "Test 1 - sink param: ", id
  Used(Token(id: id))

discard createToken("test-sink").consume()

# =============================================================================
# Test 2: var parameter (mutable state)
# =============================================================================

type
  Counter = object
    value: int
  Zero = distinct Counter
  NonZero = distinct Counter

typestate Counter:
  consumeOnTransition = false
  states Zero, NonZero
  transitions:
    Zero -> NonZero
    NonZero -> Zero

proc increment(c: var Zero): NonZero {.transition.} =
  ## Increment counter - takes mutable reference
  var counter = Counter(c)
  counter.value += 1
  echo "Test 2 - var param: ", counter.value
  NonZero(counter)

var z = Zero(Counter(value: 0))
discard z.increment()

# =============================================================================
# Test 3: Generic with sink
# =============================================================================

type
  Box[T] = object
    value: T
  Sealed[T] = distinct Box[T]
  Opened[T] = distinct Box[T]

typestate Box[T]:
  consumeOnTransition = false
  states Sealed[T], Opened[T]
  transitions:
    Sealed[T] -> Opened[T]

proc open[T](box: sink Sealed[T]): Opened[T] {.transition.} =
  echo "Test 3 - generic sink: opened"
  Opened[T](Box[T](box))

discard Sealed[int](Box[int](value: 42)).open()

echo "All type modifier tests passed!"
