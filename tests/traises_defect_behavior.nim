## Test demonstrating that Defects are NOT tracked by raises.
## This test SHOULD compile - Defects are bugs, not catchable errors.

import ../src/typestates

type
  Container = object
    items: seq[int]
  Empty = distinct Container
  HasItems = distinct Container

typestate Container:
  states Empty, HasItems
  transitions:
    Empty -> HasItems
    HasItems -> Empty

# This compiles even though seq[0] can raise IndexDefect
# Defects are NOT tracked by {.raises.} - they're bugs
proc getFirst(c: HasItems): int {.noSideEffect.} =
  c.Container.items[0]  # Could raise IndexDefect if items is empty

proc addItem(c: Empty, item: int): HasItems {.transition.} =
  result = HasItems(c)
  result.Container.items.add(item)

proc clear(c: HasItems): Empty {.transition.} =
  result = Empty(c)
  result.Container.items = @[]

# Demonstrate proper usage
when isMainModule:
  var c = Empty(Container(items: @[]))
  let withItems = c.addItem(42)
  echo "First item: ", withItems.getFirst()  # Safe - we just added an item
  echo "Defect behavior test passed - Defects are not tracked by raises"
