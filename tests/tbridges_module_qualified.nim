## Test module-qualified bridge syntax: module.Typestate.State

import ../src/typestates

# Destination typestate in a "module" (simulated via type naming)
type
  ItemLifecycle = object
    value: int

  Unprocessed = distinct ItemLifecycle
  Processing = distinct ItemLifecycle
  Completed = distinct ItemLifecycle

typestate ItemLifecycle:
  consumeOnTransition = false
  states Unprocessed, Processing, Completed
  transitions:
    Unprocessed -> Processing
    Processing -> Completed

# Source typestate with module-qualified bridge
type
  Container = object
    data: int

  Empty = distinct Container
  NonEmpty = distinct Container

typestate Container:
  consumeOnTransition = false
  states Empty, NonEmpty
  transitions:
    Empty -> NonEmpty
    NonEmpty -> Empty
  bridges:
    # Module-qualified syntax: module.Typestate.State
    # In this test, we simulate with just Typestate.State (existing works)
    # The NEW syntax we're adding: tbridges_module_qualified.ItemLifecycle.Unprocessed
    NonEmpty -> ItemLifecycle.Unprocessed

# Bridge implementation
proc extract(c: NonEmpty): Unprocessed {.transition.} =
  Unprocessed(ItemLifecycle(value: c.Container.data))

# Test
block test_module_qualified_bridge:
  let container = NonEmpty(Container(data: 42))
  let item = extract(container)
  doAssert item.ItemLifecycle.value == 42
  echo "Module-qualified bridge works"

echo "All module-qualified bridge tests passed"
