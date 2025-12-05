## Test generic typestate with static int parameters.
##
## Verifies that typestates with `N: static int` parameters work correctly.
## This is common for fixed-size data structures like arrays and ring buffers.

import ../src/typestates

# Test: Static int generic parameter
type
  VirtualValue*[N: static int] = object
    ## Base type for N-slot virtual values.
    v: int

  RawLoaded*[N: static int] = distinct VirtualValue[N]
    ## Just loaded from atomic - not yet validated.

  Wrapped*[N: static int] = distinct VirtualValue[N]
    ## Validated to be in range 0..<2*N.

typestate VirtualValue[N: static int]:
  states RawLoaded[N], Wrapped[N]
  transitions:
    RawLoaded[N] -> Wrapped[N]

proc validate*[N: static int](r: RawLoaded[N]): Wrapped[N] {.transition.} =
  ## Validate a raw loaded value.
  var base = VirtualValue[N](r)
  # In real code, would check 0..<2*N
  if base.v < 0 or base.v >= 2 * N:
    base.v = base.v mod (2 * N)
  result = Wrapped[N](base)

proc getValue*[N: static int](w: Wrapped[N]): int {.notATransition.} =
  ## Get the validated value.
  VirtualValue[N](w).v

# Run tests
block test1:
  let raw = RawLoaded[4](VirtualValue[4](v: 3))
  let wrapped = raw.validate()
  doAssert wrapped.getValue() == 3
  echo "Test 1: Basic static int typestate - PASSED"

block test2:
  let raw = RawLoaded[8](VirtualValue[8](v: 10))
  let wrapped = raw.validate()
  doAssert wrapped.getValue() == 10
  echo "Test 2: Different static int value - PASSED"

block test3:
  # Test wraparound behavior
  let raw = RawLoaded[4](VirtualValue[4](v: 10))  # 10 >= 2*4
  let wrapped = raw.validate()
  doAssert wrapped.getValue() == 2  # 10 mod 8 = 2
  echo "Test 3: Value wraparound - PASSED"

echo "All static int generic typestate tests passed!"
