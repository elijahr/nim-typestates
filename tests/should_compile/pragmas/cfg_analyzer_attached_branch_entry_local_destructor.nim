## Test (positive — §3.7 attached entry-set local survives a branch
## reconciliation WITH destructor): mirror of
## `cfg_analyzer_attached_branch_entry_local_drops_link.nim` but the
## attached holder type carries a `{.destructorTransition.}`. The
## destructor is registered against the OBJECT type only — NOT against
## the typestate state name — so the analyzer's fall-through
## destructor lookup MUST key on `attachedTypeName` for the lookup to
## hit. If `reconcileBranches` drops `attachedTypeName` from the merged
## LocalTypestate entry (pre-round-8 behavior), the lookup falls back
## to `stateType` (`ScannerOnline`), misses, and CFG-001 false-fires.
##
## Round-8 regression test (positive path lock-in). Pre-fix this
## fixture would have false-fired CFG-001 because the
## reconcileBranches merge stripped `attachedTypeName`, regressing
## the round-6 destructor-lookup-key contract for the specific path
## where an attached local crosses a branch join. Post-fix the field
## survives the merge and the destructor hit is preserved.
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

# Attached holder type WITH destructor. Destructor is registered
# against `ScannerSession` (the OBJECT type), keyed under the
# attached-type name in destructorTypes — NOT under `ScannerOnline`.
type ScannerSession {.ScannerContext: ScannerOnline.} = object
  payload: int

proc `=destroy`(s: var ScannerSession) {.destructorTransition.} =
  discard

proc runScanner(src: sink ScannerOnline, cond: bool): ScannerOffline {.transition.} =
  ## `s` is declared OUTSIDE the if-branches → present in entry set.
  ## Neither branch touches it. reconcileBranches merges the entry-set
  ## local via the all-same path. Round-8 fix preserves
  ## `attachedTypeName=ScannerSession` through the merge, so the
  ## fall-through destructor lookup keys correctly on the holder type
  ## and hits the registered `{.destructorTransition.}` — clean.
  var s {.used.}: ScannerSession
  if cond: discard else: discard
  result = ScannerOffline(src.ScannerBase)

verifyTypestates()
discard runScanner(ScannerOnline(ScannerBase(handle: 0)), true)
echo "cfg_analyzer_attached_branch_entry_local_destructor ok"
