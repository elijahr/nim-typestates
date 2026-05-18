## Test: §3.7 attached local with a `{.destructorTransition.}` reaches
## the terminal state via destructor injection — clean.
##
## Round-6 regression test (positive case). The attached object
## `PinnedAlloc` is bound to typestate `Allocator` with initial state
## `Allocated`. A destructor is registered against the OBJECT TYPE
## (`var PinnedAlloc`), keyed under the attached type name in the
## analyzer's destructorTypes table.
##
## A proc declares `var a: PinnedAlloc`, which the round-6 fix tracks
## with stateType=`Allocated` and attachedTypeName=`PinnedAlloc`. The
## proc body does NOT advance `a` to terminal — but the destructor will
## inject `=destroy` at fall-through, transitioning `a` to terminal.
##
## Validates the path-(b) destructor-lookup-key contract: the analyzer
## must key the lookup on `attachedTypeName` ("PinnedAlloc"), not on
## `stateType` ("Allocated"). Pre-round-6 this fixture would have
## false-fired CFG-001 because the lookup keyed only on stateType.
import ../../../src/typestates

type
  Allocated = object
  Freed = object

typestate Allocator:
  consumeOnTransition = false
  strictTransitions = false
  states Allocated, Freed
  initial:
    Allocated
  terminal:
    Freed
  transitions:
    Allocated -> Freed

# Attached object type. Destructor is registered against `PinnedAlloc`
# (the OBJECT type), not against `Allocated` (the state).
type PinnedAlloc {.Allocator: Allocated.} = object
  payload: int

proc `=destroy`(p: var PinnedAlloc) {.destructorTransition.} =
  discard

proc allocAndForget() =
  ## `a` is an attached local: stateType=Allocated, attachedTypeName=
  ## PinnedAlloc. Body does NOT advance it. The destructor injection
  ## at fall-through transitions to Freed (terminal) — CLEAN.
  var a: PinnedAlloc
  discard a.payload

verifyTypestates()
allocAndForget()
echo "cfg_analyzer_attached_local_destructor_terminal ok"
