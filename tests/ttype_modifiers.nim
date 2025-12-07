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

# =============================================================================
# Test 4: ref parameter (reference type)
# =============================================================================

type
  Session = object
    id: string
  Inactive = distinct Session
  Active = distinct Session

typestate Session:
  consumeOnTransition = false
  states Inactive, Active
  transitions:
    Inactive -> Active
    Active -> Inactive

proc activate(s: ref Inactive): ref Active {.transition.} =
  echo "Test 4 - ref param: activated"
  cast[ref Active](s)

var inactiveRef = new(Inactive)
inactiveRef[] = Inactive(Session(id: "sess-1"))
discard inactiveRef.activate()

# =============================================================================
# Test 5: ptr parameter (pointer type)
# =============================================================================

type
  Buffer = object
    data: int
  Empty = distinct Buffer
  Full = distinct Buffer

typestate Buffer:
  consumeOnTransition = false
  states Empty, Full
  transitions:
    Empty -> Full
    Full -> Empty

proc fill(b: ptr Empty, value: int): ptr Full {.transition.} =
  echo "Test 5 - ptr param: filled with ", value
  cast[ptr Full](b)

var bufferData = Empty(Buffer(data: 0))
discard addr(bufferData).fill(42)

echo "All type modifier tests passed!"
