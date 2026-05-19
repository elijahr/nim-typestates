## Test (DT-002, round-16): destructorTransition on an exported, extra-pragma
## proc that is NOT `=destroy`. The PragmaExpr unwrap added in round-16 must
## still surface the correct proc-name diagnostic — it must not mask the name
## error by treating the PragmaExpr as an opaque blob.
# expects: "may only be applied to a `=destroy` hook"
import ../../../src/typestates

type
  Box = object
  Full = distinct Box
  Empty = distinct Box

typestate Box:
  consumeOnTransition = false
  strictTransitions = false
  states Full, Empty
  initial:
    Full
  terminal:
    Empty
  transitions:
    Full -> Empty

# Wrong: destructorTransition on an exported, pragma-decorated proc that is
# not `=destroy`. Post-round-16 the PragmaExpr-aware extractor recovers the
# bare proc name `consume` and DT-002 fires correctly.
proc consume*(f: var Full) {.inline, destructorTransition.} =
  discard
