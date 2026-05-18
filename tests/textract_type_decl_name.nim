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
