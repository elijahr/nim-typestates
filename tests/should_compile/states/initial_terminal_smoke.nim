## DSL keyword smoke: initial: and terminal: blocks compile cleanly with no warnings.
import ../../../src/typestates

type
  X = object
  A = distinct X
  B = distinct X

typestate X:
  consumeOnTransition = false
  states A, B
  initial:
    A
  terminal:
    B
  transitions:
    A -> B

proc go(x: A): B {.transition.} =
  B(X(x))

let a = A(X())
doAssert $a == "A"
let b = a.go()
doAssert $b == "B"
echo "initial_terminal_smoke ok"
