## AST-verify fixture (GROUP C, robustness): two overloads of `step` on a
## strict typestate. The first overload is correctly marked via a COMBINED
## pragma block `{.raises: [], transition.}`; the second overload is UNMARKED.
##
## Correct (AST) result: EXACTLY ONE `fcUnmarkedProcStrict` error, anchored to
## the line of the unmarked overload only.
##
## Old text scanner: emits TWO findings. The combined-pragma overload is
## false-flagged (it cannot see `transition` inside the combined block), and
## the genuinely unmarked overload is flagged too. The count (2) and the line
## anchoring both diverge from the correct single finding.
import ../../../src/typestates

type
  Conn = object
  A = distinct Conn
  B = distinct Conn

typestate Conn:
  consumeOnTransition = false
  states A, B
  transitions:
    A -> B

proc step(c: A): B {.raises: [], transition.} =
  result = B(c)

proc step(c: A, extra: int): string =
  result = "unmarked overload"
