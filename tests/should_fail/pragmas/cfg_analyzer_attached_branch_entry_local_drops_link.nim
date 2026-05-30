## Test (CFG-001 positive — §3.7 attached entry-set local survives a
## branch reconciliation, NO destructor): an attached-object local is
## declared OUTSIDE an if/else and is therefore present in the entry
## live-set going into the branches. Neither branch consumes nor
## advances it; both branches leave the local in its initial state.
## At the join point, `reconcileBranches` merges the entry-set local
## via the all-same path (line 1293). With NO `{.destructorTransition.}`
## registered against the holder type, the fall-through edge must fire
## CFG-001 naming the attached local.
##
## Round-8 regression test (negative-case lock-in). The round-8 fix
## propagates `attachedTypeName` through reconcileBranches's merged
## LocalTypestate entries so the field survives the join. This
## fixture validates that the fix does NOT over-relax the analyzer:
## an attached local with no destructor must still fire CFG-001 at
## fall-through after passing through a branch reconciliation. The
## paired `should_compile` fixture validates the destructor-hit
## path; this fixture rules out a silent swallow.
##
## Why the leaking declaration is inside a registered transition: the
## CFG analyzer's per-proc body walk runs only on procs registered
## via `{.transition.}` / `{.destructorTransition.}`. We drive a
## non-attached `sink ScannerOnline` -> `ScannerOffline` edge to
## satisfy `{.transition.}` registration; the attached `var s:
## ScannerSession` local inside the body is what exercises the
## reconcileBranches entry-set merge.
# expects: "has not reached a terminal state"
# expects: "ScannerOnline"
# expects: "ScannerContext"
import ../../../src/typestates

type
  ScannerBase = object
    handle: int

  ScannerOnline = distinct ScannerBase
  ScannerOffline = distinct ScannerBase

typestate ScannerContext:
  consumeOnTransition = false
  strictTransitions = false
  states ScannerOnline, ScannerOffline
  initial:
    ScannerOnline
  terminal:
    ScannerOffline
  transitions:
    ScannerOnline -> ScannerOffline

# Attached holder type. NO destructor registered — the leak must
# surface at fall-through.
type ScannerSession {.ScannerContext: ScannerOnline.} = object
  payload: int

proc runScanner(src: sink ScannerOnline, cond: bool): ScannerOffline {.transition.} =
  ## `s` is declared OUTSIDE the if-branches → present in entry set.
  ## Neither branch touches it. reconcileBranches merges the entry-set
  ## local via the all-same path. Post-round-8 the merge preserves
  ## `attachedTypeName=ScannerSession`; with no destructor registered
  ## the fall-through destructor lookup misses under both keys and
  ## CFG-001 fires naming `s`.
  var s {.used.}: ScannerSession
  if cond: discard else: discard
  result = ScannerOffline(src.ScannerBase)

verifyTypestates()
