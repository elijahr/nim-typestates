## Test: §3.7 typestate-attachment pragma on an EXPORTED GENERIC type
## (`type Slot*[G] = object`).
##
## Round-15 GEM-HIGH end-to-end acceptance. The natural Nim parse for
## `type Slot*[G] = object` places `nnkPostfix(*, Slot)` at TypeDef[0]
## (not a BracketExpr — the generic params live in TypeDef[1] as a
## GenericParams node). `extractTypeDeclName` handles this via its
## top-level Postfix-unwrap, but historically only the BracketExpr
## fallback was considered, leaving the recognizer fragile to any
## downstream macro that synthesizes a `BracketExpr(Postfix(*, T), G)`
## shape for the same source form. The round-15 fix peels a nested
## Postfix inside the BracketExpr branch as well; this fixture locks
## in the natural-path end-to-end behavior so the attachment-registry
## key is always the bare base name.
##
## See `tests/textract_type_decl_name.nim` for the load-bearing
## structural unit test that covers both AST shapes directly.
import ../../../src/typestates
import ../../../src/typestates/registry
import std/options

type
  SlotAlive = object
  SlotDestroyed = object

typestate SlotContext:
  consumeOnTransition = false
  strictTransitions = false
  states SlotAlive, SlotDestroyed
  initial:
    SlotAlive
  terminal:
    SlotDestroyed
  transitions:
    SlotAlive -> SlotDestroyed

# Exported AND generic. The `{.SlotContext: SlotAlive.}` pragma must
# register the attachment under the bare key `"Slot"`, with neither
# the `*` export marker nor the `[G]` generic suffix.
type Slot*[G] {.SlotContext: SlotAlive.} = object
  payload: G

verifyTypestates()

static:
  let att = findAttachmentForType("Slot")
  doAssert att.isSome,
    "typestate_attachment_exported_generic_type: Slot attachment missing — " &
      "extractTypeDeclName likely leaked the export marker or generic suffix " &
      "into the registry key"
  doAssert att.get.typestateName == "SlotContext",
    "typestate_attachment_exported_generic_type: wrong typestate name"
  doAssert att.get.initialState == "SlotAlive",
    "typestate_attachment_exported_generic_type: wrong initial state"
  # Defensive: no key with the stale export marker. `findAttachmentForType`
  # passes its argument through `extractBaseName` (registry.nim:170) which
  # strips a trailing `[...]` suffix, so `"Slot[G]"` would also resolve —
  # that's the registry's normal behavior, not a leak. The relevant
  # regression to guard against is the export marker leaking into the
  # registry key, which a starts-with-asterisk-suffix probe catches:
  doAssert findAttachmentForType("Slot*").isNone,
    "typestate_attachment_exported_generic_type: a `Slot*` key leaked"

echo "typestate_attachment_exported_generic_type ok"
