## Test (positive — §3.7 attached branch-introduced local survives a
## branch reconciliation WITH destructor): mirror of
## `cfg_analyzer_attached_branch_introduced_local_drops_link.nim` but
## the attached holder type carries a `{.destructorTransition.}`. The
## destructor is registered against the OBJECT type only, so the
## fall-through destructor lookup MUST key on `attachedTypeName` to
## hit. If `reconcileBranches`'s second-pass merge (branch-introduced
## locals, line 1392) drops `attachedTypeName`, the lookup falls back
## to `stateType` (`PortIdle`), misses, and CFG-001 false-fires.
##
## Round-8 regression test (positive path lock-in for the second-pass
## merge). Pre-fix this fixture would have false-fired CFG-001 because
## the branch-introduced reconciliation stripped `attachedTypeName`,
## regressing the round-6 destructor-lookup-key contract for
## attached locals declared inside branches. Post-fix the field
## survives and the destructor hit is preserved.
import ../../../src/typestates

type
  PortBase = object
    handle: int

  PortIdle = distinct PortBase
  PortReleased = distinct PortBase

typestate PortContext:
  consumeOnTransition = false
  strictTransitions = false
  states PortIdle, PortReleased
  initial:
    PortIdle
  terminal:
    PortReleased
  transitions:
    PortIdle -> PortReleased

# Attached holder type WITH destructor. Destructor is registered
# against `PortHandle` (the OBJECT type), keyed under the
# attached-type name in destructorTypes — NOT under `PortIdle`.
type PortHandle {.PortContext: PortIdle.} = object
  payload: int

proc `=destroy`(p: var PortHandle) {.destructorTransition.} =
  discard

proc routePort(src: sink PortIdle, cond: bool): PortReleased {.transition.} =
  ## `p` is declared INSIDE both branches — branch-introduced, not in
  ## entry set. Both branches leave it at PortIdle. reconcileBranches
  ## second pass propagates it into the merged live-set. Round-8 fix
  ## preserves `attachedTypeName=PortHandle` so the fall-through
  ## destructor lookup keys correctly on the holder type and hits the
  ## registered `{.destructorTransition.}` — clean.
  if cond:
    var p {.used.}: PortHandle
  else:
    var p {.used.}: PortHandle
  result = PortReleased(src.PortBase)

verifyTypestates()
discard routePort(PortIdle(PortBase(handle: 0)), true)
echo "cfg_analyzer_attached_branch_introduced_local_destructor ok"
