## Test: Basic §3.7 typestate-attachment pragma (positive case).
##
## Declares a typestate whose name does NOT collide with any underlying
## object type (so the per-typestate marker macro IS emitted by the
## `typestate` macro), then attaches an object type to it via
## `{.<TypestateName>: <InitialState>.}` and verifies:
##
## 1. The pragma form parses and compiles cleanly.
## 2. The attachment is registered in `typestateAttachments` so
##    `findAttachmentForType` returns the expected `AttachmentInfo`.
## 3. A `{.destructorTransition.}` on the attached object's `=destroy`
##    successfully resolves its source state via path (b) of §3.1 (the
##    attachment-fallback path) — proving end-to-end integration with
##    `destructorTransitionCore`.
import ../../../src/typestates
import ../../../src/typestates/registry
import std/options

# State types for the typestate. These are the actual "states" tracked
# by the analyzer.
type
  PinnedScopeAlive = object
    handle: int

  PinnedScopeDestroyed = object
    handle: int

typestate PinnedScopeContext:
  consumeOnTransition = false
  strictTransitions = false
  states PinnedScopeAlive, PinnedScopeDestroyed
  initial:
    PinnedScopeAlive
  terminal:
    PinnedScopeDestroyed
  transitions:
    PinnedScopeAlive -> PinnedScopeDestroyed

# Attached object type — the `{.PinnedScopeContext: PinnedScopeAlive.}`
# pragma binds it to the typestate above with initial state
# `PinnedScopeAlive`.
type PinnedScope* {.PinnedScopeContext: PinnedScopeAlive.} = object
  payload: int

# Destructor on the ATTACHED OBJECT type (not on a state) — exercises
# §3.1 path (b) (attachment-fallback source resolution). Before §3.7
# was implemented this would fail with DT-006.
proc `=destroy`(s: var PinnedScope) {.destructorTransition.} =
  discard

verifyTypestates()

# Compile-time assertion: the registry actually contains the binding.
static:
  let att = findAttachmentForType("PinnedScope")
  doAssert att.isSome, "typestate_attachment_basic: PinnedScope attachment missing"
  doAssert att.get.typestateName == "PinnedScopeContext",
    "typestate_attachment_basic: wrong typestate name"
  doAssert att.get.initialState == "PinnedScopeAlive",
    "typestate_attachment_basic: wrong initial state"

echo "typestate_attachment_basic ok"
