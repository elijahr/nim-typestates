## Test: Same generic typestate used with different concrete types
import ../../../src/typestates

type
  Stack[T] = object
    items: seq[T]
  EmptyStack[T] = distinct Stack[T]
  NonEmptyStack[T] = distinct Stack[T]

typestate Stack[T]:
  consumeOnTransition = false  # Opt out for existing tests
  strictTransitions = false
  states EmptyStack[T], NonEmptyStack[T]
  transitions:
    EmptyStack[T] -> NonEmptyStack[T]
    NonEmptyStack[T] -> EmptyStack[T]
    NonEmptyStack[T] -> NonEmptyStack[T]

proc push[T](s: EmptyStack[T], val: T): NonEmptyStack[T] {.transition.} =
  var stack = Stack[T](s)
  stack.items.add(val)
  NonEmptyStack[T](stack)

proc pushMore[T](s: NonEmptyStack[T], val: T): NonEmptyStack[T] {.transition.} =
  var stack = Stack[T](s)
  stack.items.add(val)
  NonEmptyStack[T](stack)

# Test with int
let intStack = EmptyStack[int](Stack[int](items: @[]))
let intWithOne = intStack.push(42)
doAssert Stack[int](intWithOne).items == @[42]

# Test with string
let strStack = EmptyStack[string](Stack[string](items: @[]))
let strWithOne = strStack.push("hello")
let strWithTwo = strWithOne.pushMore("world")
doAssert Stack[string](strWithTwo).items == @["hello", "world"]

echo "concrete_instantiation test passed"
