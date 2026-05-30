## Test: §3.7 typestate-attachment pragma on an EXPORTED (`*`) type.
##
## Round-15 GEM-HIGH end-to-end acceptance. `extractTypeDeclName` must
## return the bare base name (`PinnedScope`, no trailing `*`) when the
## attached type is declared with the `*` export marker. Pre-r15 the
## natural Nim parse `type T* = object` was already handled by the
## top-level Postfix-unwrap, but the defensive BracketExpr-with-
## nested-Postfix path was uncovered. This fixture exercises the
## natural path end-to-end so any regression that lets the export
## marker leak into the attachment-registry key surfaces as a runtime
## `doAssert` failure on `findAttachmentForType("PinnedScope")`.
##
## See `tests/textract_type_decl_name.nim` for the load-bearing
## structural unit test that covers all four input shapes
## (`T`, `T*`, `T[G]`, `T*[G]`) directly.
import ../../../src/typestates
import ../../../src/typestates/registry
import std/options

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

# Attached object — note the `*` export marker on the type name. The
# `{.PinnedScopeContext: PinnedScopeAlive.}` pragma must register the
# attachment under the bare key `"PinnedScope"`, not `"PinnedScope*"`.
type PinnedScope* {.PinnedScopeContext: PinnedScopeAlive.} = object
  payload: int

proc `=destroy`(s: var PinnedScope) {.destructorTransition.} =
  discard

verifyTypestates()

static:
  let att = findAttachmentForType("PinnedScope")
  doAssert att.isSome,
    "typestate_attachment_exported_type: PinnedScope attachment missing — " &
      "extractTypeDeclName likely leaked the export marker into the registry key"
  doAssert att.get.typestateName == "PinnedScopeContext",
    "typestate_attachment_exported_type: wrong typestate name"
  doAssert att.get.initialState == "PinnedScopeAlive",
    "typestate_attachment_exported_type: wrong initial state"
  # Defensive: ensure no key with the stale export marker exists.
  let bogus = findAttachmentForType("PinnedScope*")
  doAssert bogus.isNone,
    "typestate_attachment_exported_type: a `PinnedScope*` key leaked into the registry"

echo "typestate_attachment_exported_type ok"
