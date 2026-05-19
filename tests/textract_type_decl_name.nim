## Structural unit tests for `extractTypeDeclName` (pragmas.nim:1038).
##
## Round-15 GEM-HIGH acceptance test: drives `extractTypeDeclName`
## directly across every TypeDef head-shape the §3.7 attachment
## pragma encounters in practice. Each branch of the case dispatch
## corresponds to a distinct AST class the macro layer must collapse
## to the bare type name so attachment-registry keys are export-marker
## free and generic-bracket free.
##
## Pre-round-15 the `nnkBracketExpr` branch checked only `Ident/Sym`
## at the bracket head; the fallback `head.repr` returned the name
## with the stale `*` export marker on the (rarely-produced) shape
## `BracketExpr(Postfix(*, T), G)`. Post-fix the bracket-expr branch
## peels a nested `nnkPostfix` first, mirroring the top-level
## Postfix-unwrap already in place.
##
## The natural Nim parse of `type T*[G] = object` places `Postfix`
## at the TypeDef head (handled by the top-level unwrap on
## pragmas.nim line 1053), so the BracketExpr-with-nested-Postfix
## shape is defensive — but a hand-built TypeDef from a downstream
## macro could produce it, and this test locks the recognizer in
## either way. The four shapes covered (`T`, `T*`, `T[G]`, `T*[G]`)
## together exercise the four `case` branches plus the Postfix-peel
## edges. Mirrors the round-13 `textract_callee_name.nim` pattern.

import std/unittest
import std/macros

import ../src/typestates/pragmas

# `extractTypeDeclName` is `{.compileTime.}`, so every assertion runs
# inside a `static:` block. The `result` variable in each block is a
# captured runtime string that the unittest framework then checks
# against the expected value.

suite "extractTypeDeclName TypeDef head-shape recognizer":
  test "bare type: `type T = object`":
    const got = static:
      let typeDef = nnkTypeDef.newTree(
        ident("Slot"),
        newEmptyNode(),
        nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), newEmptyNode()),
      )
      extractTypeDeclName(typeDef)
    check got == "Slot"

  test "exported type: `type T* = object`":
    const got = static:
      let postfix = nnkPostfix.newTree(ident("*"), ident("Slot"))
      let typeDef = nnkTypeDef.newTree(
        postfix,
        newEmptyNode(),
        nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), newEmptyNode()),
      )
      extractTypeDeclName(typeDef)
    check got == "Slot"

  test "generic type: `type T[G] = object`":
    ## Natural Nim parse for `type T[G] = object` keeps the name at
    ## TypeDef[0] as a bare Ident and moves the generic params to
    ## TypeDef[1] as a GenericParams node — there is no BracketExpr
    ## in the natural AST. This test hand-builds the BracketExpr
    ## shape to exercise the BracketExpr branch directly, which is
    ## the path used by downstream macros that synthesize TypeDef
    ## ASTs (or by any caller threading through quote-do).
    const got = static:
      let bracket = nnkBracketExpr.newTree(ident("Slot"), ident("G"))
      let typeDef = nnkTypeDef.newTree(
        bracket,
        newEmptyNode(),
        nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), newEmptyNode()),
      )
      extractTypeDeclName(typeDef)
    check got == "Slot"

  test "exported generic type: `type T*[G] = object` — GEM-HIGH":
    ## Round-15 acceptance for Gemini r14's HIGH finding. Two AST
    ## shapes are possible for `type T*[G] = object`:
    ##
    ## (1) Natural Nim parse: `TypeDef[ Postfix(*, T), GenericParams[G], ObjectTy ]`
    ##     — the top-level Postfix-unwrap handles this; the bracket
    ##     branch is never reached.
    ##
    ## (2) Hand-built / downstream-macro shape:
    ##     `TypeDef[ BracketExpr(Postfix(*, T), G), Empty, ObjectTy ]`
    ##     — pre-fix the BracketExpr branch's `head.kind in
    ##     {Ident, Sym}` check failed (head is Postfix), the fallback
    ##     returned `head.repr` = `"T*"` (with stale export marker),
    ##     and §3.7 attachment-registry lookups missed because they
    ##     keyed off the un-marker name.
    ##
    ## Both shapes must collapse to the bare `"Slot"`.
    block shape_one_natural_parse:
      const got = static:
        let postfix = nnkPostfix.newTree(ident("*"), ident("Slot"))
        let typeDef = nnkTypeDef.newTree(
          postfix,
          nnkGenericParams.newTree(
            nnkIdentDefs.newTree(ident("G"), newEmptyNode(), newEmptyNode())
          ),
          nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), newEmptyNode()),
        )
        extractTypeDeclName(typeDef)
      check got == "Slot"
    block shape_two_hand_built_bracket:
      const got = static:
        let postfix = nnkPostfix.newTree(ident("*"), ident("Slot"))
        let bracket = nnkBracketExpr.newTree(postfix, ident("G"))
        let typeDef = nnkTypeDef.newTree(
          bracket,
          newEmptyNode(),
          nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), newEmptyNode()),
        )
        extractTypeDeclName(typeDef)
      check got == "Slot"

  test "pragma-wrapped exported type: `type T* {.p.} = object`":
    ## When a pragma is attached, `typeDef[0]` is wrapped in
    ## `nnkPragmaExpr[NameNode, Pragma]`. The PragmaExpr-unwrap then
    ## drops to the underlying Postfix.
    const got = static:
      let postfix = nnkPostfix.newTree(ident("*"), ident("Slot"))
      let pragmaExpr = nnkPragmaExpr.newTree(postfix, nnkPragma.newTree(ident("dummy")))
      let typeDef = nnkTypeDef.newTree(
        pragmaExpr,
        newEmptyNode(),
        nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), newEmptyNode()),
      )
      extractTypeDeclName(typeDef)
    check got == "Slot"

  test "pragma-wrapped exported generic: `type T*[G] {.p.} = object`":
    ## End-to-end of the §3.7 attachment-pragma path: macro receives
    ## an untyped TypeDef whose [0] is `PragmaExpr[Postfix[*, T], Pragma]`
    ## and whose [1] is `GenericParams[...]`. PragmaExpr-unwrap drops
    ## to Postfix, Postfix-unwrap drops to the Ident.
    const got = static:
      let postfix = nnkPostfix.newTree(ident("*"), ident("Slot"))
      let pragmaExpr = nnkPragmaExpr.newTree(postfix, nnkPragma.newTree(ident("dummy")))
      let typeDef = nnkTypeDef.newTree(
        pragmaExpr,
        nnkGenericParams.newTree(
          nnkIdentDefs.newTree(ident("G"), newEmptyNode(), newEmptyNode())
        ),
        nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), newEmptyNode()),
      )
      extractTypeDeclName(typeDef)
    check got == "Slot"

  test "backticked type: `type \\`foo\\` = object`":
    ## Round-18 GEM-MED-2 acceptance. Backticked type names parse with
    ## `nnkAccQuoted` at the TypeDef head. Pre-fix the case dispatch fell
    ## through to `nameNode.repr`, which preserves the surrounding
    ## backticks; attachment-registry lookups keyed off the bare name
    ## would miss. Post-fix the explicit `nnkAccQuoted` branch reassembles
    ## the bare identifier via `accQuotedToStr` (matching
    ## `extractTypestatedParams` and `destructorTransitionCore`).
    const got = static:
      let accQuoted = nnkAccQuoted.newTree(ident("foo"))
      let typeDef = nnkTypeDef.newTree(
        accQuoted,
        newEmptyNode(),
        nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), newEmptyNode()),
      )
      extractTypeDeclName(typeDef)
    check got == "foo"

  test "exported backticked type: `type \\`foo\\`* = object`":
    ## Round-18 GEM-MED-2 acceptance. Top-level `nnkPostfix` wraps
    ## `nnkAccQuoted`. `peelNameWrappers` strips the Postfix, then the
    ## new `nnkAccQuoted` dispatch branch handles the leaf.
    const got = static:
      let accQuoted = nnkAccQuoted.newTree(ident("foo"))
      let postfix = nnkPostfix.newTree(ident("*"), accQuoted)
      let typeDef = nnkTypeDef.newTree(
        postfix,
        newEmptyNode(),
        nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), newEmptyNode()),
      )
      extractTypeDeclName(typeDef)
    check got == "foo"

  test "exported backticked generic: `type \\`foo\\`*[G] = object` (hand-built bracket)":
    ## Round-18 GEM-MED-2 acceptance for the BracketExpr-head path. The
    ## hand-built shape is `BracketExpr(Postfix(*, AccQuoted(foo)), G)`.
    ## `peelNameWrappers` on the bracket head strips the Postfix, leaving
    ## the AccQuoted leaf for the new `nnkAccQuoted` dispatch branch
    ## inside the BracketExpr case.
    const got = static:
      let accQuoted = nnkAccQuoted.newTree(ident("foo"))
      let postfix = nnkPostfix.newTree(ident("*"), accQuoted)
      let bracket = nnkBracketExpr.newTree(postfix, ident("G"))
      let typeDef = nnkTypeDef.newTree(
        bracket,
        newEmptyNode(),
        nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), newEmptyNode()),
      )
      extractTypeDeclName(typeDef)
    check got == "foo"

  test "peelNameWrappers loops through arbitrary wrapper nesting (GEM-MED-1)":
    ## Round-18 GEM-MED-1 acceptance. The r17 helper was single-pass
    ## (one PragmaExpr peel followed by one Postfix peel). Inverse
    ## orderings (`Postfix(PragmaExpr(...))`) and deeper nestings would
    ## leave residual wrappers on the returned node. Post-fix the helper
    ## loops until a leaf, so every arbitrary nesting of
    ## {PragmaExpr, Postfix} collapses to the underlying leaf. Hand-built
    ## ASTs only — Nim's parser produces just the `PragmaExpr(Postfix)`
    ## shape, but downstream macros that synthesize TypeDef / ProcDef
    ## ASTs may emit either order or recurse deeper.
    ##
    ## Exercised via `extractTypeDeclName` which is the only currently
    ## exported caller; this keeps the helper's behaviour observable
    ## without coupling the test to its internal symbol.
    block inverse_order_postfix_outside_pragmaexpr:
      ## `Postfix(*, PragmaExpr(Ident, Pragma))` — inverse of the parser
      ## shape. Single-pass would peel the Postfix and return the
      ## PragmaExpr unchanged; the loop continues and unwraps.
      const got = static:
        let inner =
          nnkPragmaExpr.newTree(ident("Slot"), nnkPragma.newTree(ident("dummy")))
        let postfix = nnkPostfix.newTree(ident("*"), inner)
        let typeDef = nnkTypeDef.newTree(
          postfix,
          newEmptyNode(),
          nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), newEmptyNode()),
        )
        extractTypeDeclName(typeDef)
      check got == "Slot"
    block deeper_nesting_pragmaexpr_postfix_pragmaexpr:
      ## `PragmaExpr(Postfix(*, PragmaExpr(Ident, P1)), P2)` — three
      ## wrappers deep. Single-pass peeled the outer two and stopped on
      ## the residual inner PragmaExpr; the loop drains all three.
      const got = static:
        let innerPragma =
          nnkPragmaExpr.newTree(ident("Slot"), nnkPragma.newTree(ident("p1")))
        let postfix = nnkPostfix.newTree(ident("*"), innerPragma)
        let outerPragma = nnkPragmaExpr.newTree(postfix, nnkPragma.newTree(ident("p2")))
        let typeDef = nnkTypeDef.newTree(
          outerPragma,
          newEmptyNode(),
          nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), newEmptyNode()),
        )
        extractTypeDeclName(typeDef)
      check got == "Slot"
    block double_postfix_theoretical:
      ## `Postfix(*, Postfix(*, Ident))` — theoretical hand-built shape.
      ## Single-pass peeled one Postfix; the loop peels both.
      const got = static:
        let inner = nnkPostfix.newTree(ident("*"), ident("Slot"))
        let outer = nnkPostfix.newTree(ident("*"), inner)
        let typeDef = nnkTypeDef.newTree(
          outer,
          newEmptyNode(),
          nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), newEmptyNode()),
        )
        extractTypeDeclName(typeDef)
      check got == "Slot"
