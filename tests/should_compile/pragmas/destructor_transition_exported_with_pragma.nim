## Test: `{.destructorTransition.}` accepts an exported `=destroy` hook that
## carries additional pragmas alongside the destructor-transition marker.
##
## Round-16 acceptance for Gemini r15's HIGH finding #2:
## `destructorTransitionCore` previously read the proc-name node by
## peeling only a top-level `nnkPostfix`. When a `=destroy` hook is BOTH
## exported AND carries extra pragmas (e.g. `{.inline, destructorTransition.}`),
## Nim parses the proc-name slot as
## `PragmaExpr(Postfix(*, AccQuoted(=, destroy)), Pragma)`. Pre-fix, the
## Postfix-only peel left the PragmaExpr in place, the case-dispatch
## fell through to `procNameNode.repr`, and the
## `procName != "=destroy"` discriminator failed with a misleading
## diagnostic.
##
## Post-fix the proc-name extractor mirrors the unwrap precedence used
## by `extractTypeDeclName` (pragmas.nim:1052-1057): PragmaExpr first,
## then Postfix, then dispatch on AccQuoted / Ident / Sym.
import ../../../src/typestates

type
  Resource = object
    handle: int

  Open = distinct Resource
  Closed = distinct Resource

typestate Resource:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Closed

# Exported destructor with an extra pragma alongside destructorTransition.
# Pre-round-16 this failed with "may only be applied to a `=destroy` hook"
# because the extracted proc name was the full PragmaExpr.repr form
# rather than the bare `=destroy` ident.
proc `=destroy`*(r: var Open) {.inline, destructorTransition.} =
  discard

verifyTypestates()
echo "destructor_transition_exported_with_pragma ok"
