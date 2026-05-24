## AST-verify fixture (GROUP B): an UNMARKED proc whose first param is
## `out <State>` on a STRICT typestate. The `out` modifier parses as a dedicated
## `nkOutTy` node and must be peeled to recognize the underlying typestate state.
##
## Correct (AST) result: ONE `fcUnmarkedProcStrict` error.
##
## Regression guard (v0.10.0 modifier-node audit): before `nkOutTy` was added to
## `peelableModifierTyKinds`, `peelToBaseTypeName` fell through to the render
## fallback and resolved the param type to the literal `out Open`, which is not a
## member of `states`, so the unmarked proc was silently NOT flagged
## (false-negative). With the fix, the `out` wrapper is peeled to `Open` and the
## proc is correctly flagged.
import ../../../src/typestates

type
  Door = object
  Open = distinct Door
  Closed = distinct Door

typestate Door:
  consumeOnTransition = false
  states Open, Closed
  transitions:
    Open -> Closed

proc fill(f: out Open) =
  discard
