## AST-verify fixture (pepper edge-flag 2b — distinct over-peel guard): a STRICT
## typestate plus a `distinct` alias of a NON-state type used as a proc param.
##
## `peelToBaseTypeName` must NOT transitively peel a distinct alias through to
## its underlying base. The alias `Token` is `distinct int` — a brand new type
## that is NOT a typestate state. The proc taking `Token` must therefore be
## treated as having no typestate param and must NOT be mis-classified as
## operating on a state (no false `fcUnmarkedProcStrict` finding via over-peel).
##
## Correct (AST) result: NO finding for `useToken` — its param is not a state.
## (The genuine state procs below are properly marked, so the file as a whole
## must produce zero findings.)
import ../../../src/typestates

type
  Gate = object
  Open = distinct Gate
  Closed = distinct Gate
  Token = distinct int ## non-state distinct alias; must NOT peel to a state

typestate Gate:
  consumeOnTransition = false
  states Open, Closed
  transitions:
    Open -> Closed

proc seal(g: Open): Closed {.transition.} =
  Closed(g)

proc useToken(t: Token): int {.raises: [].} =
  ## Unmarked, but its param is a non-state distinct alias, so it must NOT be
  ## flagged. If `peelToBaseTypeName` wrongly peeled `Token` -> `int` -> (or
  ## worse, a state), this would falsely register as a typestate proc.
  result = 0
