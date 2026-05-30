## AST-verify fixture (GROUP C, robustness / over-match guard): procs whose
## params are ALL non-typestate types (int, string). No param touches a
## typestate state, so the transition-marking rule does not apply.
##
## Correct result: NO finding (and these procs must NOT be counted as
## transitions either).
##
## Old text scanner: also emits nothing here. Included as an over-match guard
## so the AST rewrite does not start flagging unrelated procs.
import ../../../src/typestates

type
  Widget = object
  Cold = distinct Widget
  Hot = distinct Widget

typestate Widget:
  consumeOnTransition = false
  states Cold, Hot
  transitions:
    Cold -> Hot

proc add(a: int, b: int): int =
  result = a + b

proc greet(name: string): string =
  result = "hi " & name
