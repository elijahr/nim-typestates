## Fixture: initial:/terminal: blocks with multi-line lists.
## Used by tast_parser.nim to verify nkStmtList traversal.
import ../../src/typestates

type
  M = object
  A = distinct M
  B = distinct M
  C = distinct M
  D = distinct M
  E = distinct M

typestate M:
  consumeOnTransition = false
  states A, B, C, D, E
  initial:
    A
    B
  terminal:
    D
    E
  transitions:
    A -> C
    B -> C
    C -> D
    C -> E

proc go(a: A): C {.transition.} =
  C(M(a))
