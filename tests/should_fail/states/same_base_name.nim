## Test that same-base-name states are rejected with a clear error.
##
## This test should FAIL to compile with an informative error message
## explaining why wrapper types are needed.

import std/options

type
  Direction = enum
    Input
    Output

  GPIO[TEnabled: static bool, TDir: static Option[Direction]] = object
    pin: int

import ../../../src/typestates

typestate GPIO[TEnabled: static bool, TDir: static Option[Direction]]:
  consumeOnTransition = false # Opt out for existing tests
  states GPIO[false, none(Direction)],
    GPIO[true, none(Direction)], GPIO[true, some(Input)]
  transitions:
    GPIO[false, none(Direction)] -> GPIO[true, none(Direction)]
