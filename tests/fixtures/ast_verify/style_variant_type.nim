## AST-verify fixture (style-insensitivity, type names): a typestate state is
## registered as `MyState`, but an UNMARKED proc types its first parameter in a
## DIFFERENT-but-equivalent Nim style (`my_state`). Nim treats identifiers
## style-insensitively (first char case-sensitive, the rest case-insensitive,
## underscores ignored), so `my_state` and `MyState` differ ONLY in their first
## letter (`m` vs `M`) — those are DISTINCT identifiers and must NOT match.
##
## The genuinely-equivalent variant `My_State` (same first letter, underscore
## ignored, rest case-folded) IS the same identifier as `MyState` and MUST be
## recognized as the registered state base.
##
## Correct (AST) result: ONE `fcUnmarkedProcStrict` error — for the proc whose
## param is typed `My_State` (== `MyState`). The `my_state` proc differs in
## first-letter case and is therefore NOT a typestate-state param, so it is not
## flagged.
##
## Regression guard: a verifier that compares RAW identifier strings would skip
## the `My_State` proc (raw `My_State` != raw `MyState`), emitting ZERO errors.
import ../../../src/typestates

type
  Holder = object
  MyState = distinct Holder
  Other = distinct Holder

typestate Holder:
  consumeOnTransition = false
  states MyState, Other
  transitions:
    MyState -> Other

# Same identifier as `MyState` (underscore ignored, rest case-folded), so this
# IS a typestate-state param and, being unmarked on a strict typestate, must be
# flagged.
proc touch(s: var My_State) =
  discard

# Differs in FIRST-letter case (`m` vs `M`); under Nim's rules this is a
# DISTINCT identifier and therefore NOT a registered state param, so it must
# NOT be flagged.
proc ignore(s: var my_state) =
  discard
