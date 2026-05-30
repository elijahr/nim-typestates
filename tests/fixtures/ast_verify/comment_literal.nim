## AST-verify fixture (GROUP B): the literal text `{.notATransition.}` appears
## both in a trailing line comment AND inside a string literal on the SAME
## physical line as a genuinely UNMARKED proc on a strict typestate param.
##
## Correct (AST) result: the proc MUST be flagged `fcUnmarkedProcStrict`. A
## comment or string-literal occurrence of the marker text is NOT a pragma and
## MUST NOT be mistaken for one.
##
## Old text scanner: FALSE-NEGATIVE (green mirage). It does a raw substring
## test `"{.notATransition.}" in trimmed` against the whole `proc` line,
## including the trailing comment and the string literal. Both contain the
## literal, so the scanner believes the proc is marked notATransition and emits
## nothing.
import ../../../src/typestates

type
  Box = object
  Sealed = distinct Box
  Opened = distinct Box

typestate Box:
  consumeOnTransition = false
  states Sealed, Opened
  transitions:
    Sealed -> Opened

proc tamper(b: Sealed): string = "{.notATransition.}" # not really {.notATransition.}
