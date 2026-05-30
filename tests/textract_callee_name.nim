## Structural unit tests for `extractCalleeName` (verify.nim:336).
##
## Round-13 BOT-C2 acceptance test: drives `extractCalleeName` directly
## across every callee head-shape the CFG analyzer encounters in
## practice. Each branch of the case dispatch corresponds to a distinct
## structural class closed across rounds 3 / 5 / 8 / 9 / 12 / 13 — see
## the comment block in `extractCalleeName` for the full audit matrix.
##
## Pre-round-13 `extractCalleeName`'s `nnkBracketExpr` branch only
## accepted `head[0].kind in {nnkIdent, nnkSym}`. Module-qualified
## generic instantiations `module.foo[T](args)` parse with `head[0]`
## as `nnkDotExpr`, so the recognizer returned `""` and the analyzer
## treated the call as unrecognized — silently dropping transition
## tracking. Post-fix the bracket-expr branch recurses on the
## dot-expr's trailing identifier, mirroring the precedence of the
## top-level `nnkDotExpr` branch.
##
## These tests are structural rather than end-to-end: generic
## typestates are deferred in 0.9.0 (verify.nim:2120), so a positive
## CFG fixture cannot distinguish pre-fix from post-fix at the
## diagnostic level. The structural assertion is the load-bearing
## verification — every prior recognizer round (3 / 5 / 8 / 9 / 12)
## was a recognizer fix and could equally be locked in by a
## structural test of this shape; the round-13 fix completes the
## table.

import std/unittest
import std/macros

import ../src/typestates/verify

# `extractCalleeName` is `{.compileTime.}`, so every assertion runs
# inside a `static:` block. The `result` variable in each block is a
# captured runtime string that the unittest framework then checks
# against the expected value.

suite "extractCalleeName head-shape recognizer":
  test "bare-ident call: foo(args)":
    const got = static:
      let call = nnkCall.newTree(ident("foo"), newIntLitNode(0))
      extractCalleeName(call)
    check got == "foo"

  test "sym-choice call: foo(args) where foo is an overloaded symbol":
    const got = static:
      var choice = nnkOpenSymChoice.newTree(ident("bar"), ident("bar"))
      let call = nnkCall.newTree(choice, newIntLitNode(0))
      extractCalleeName(call)
    check got == "bar"

  test "closed sym-choice call":
    const got = static:
      var choice = nnkClosedSymChoice.newTree(ident("baz"))
      let call = nnkCall.newTree(choice)
      extractCalleeName(call)
    check got == "baz"

  test "bare generic instantiation: foo[T](args)":
    const got = static:
      let head = nnkBracketExpr.newTree(ident("foo"), ident("int"))
      let call = nnkCall.newTree(head, newIntLitNode(0))
      extractCalleeName(call)
    check got == "foo"

  test "module-qualified call: module.foo(args)":
    const got = static:
      let head = nnkDotExpr.newTree(ident("module"), ident("foo"))
      let call = nnkCall.newTree(head, newIntLitNode(0))
      extractCalleeName(call)
    check got == "foo"

  test "module-qualified generic instantiation: module.foo[T](args) — BOT-C2":
    ## Round-13 acceptance: pre-fix returned ""; post-fix returns the
    ## trailing dot-expr identifier. This is the structural test that
    ## locks in the round-13 recognizer extension and prevents
    ## regression to the silently-dropping behaviour described in
    ## the Momus r3 BOT-C2 finding.
    const got = static:
      let dot = nnkDotExpr.newTree(ident("module"), ident("foo"))
      let head = nnkBracketExpr.newTree(dot, ident("int"))
      let call = nnkCall.newTree(head, newIntLitNode(0))
      extractCalleeName(call)
    check got == "foo"

  test "generic instantiation with sym-choice head: foo[T] where foo is overloaded":
    const got = static:
      var choice = nnkOpenSymChoice.newTree(ident("qux"), ident("qux"))
      let head = nnkBracketExpr.newTree(choice, ident("int"))
      let call = nnkCall.newTree(head, newIntLitNode(0))
      extractCalleeName(call)
    check got == "qux"

  test "unrecognized shape: (expr)(args) returns empty":
    const got = static:
      let paren = nnkPar.newTree(ident("foo"))
      let call = nnkCall.newTree(paren, newIntLitNode(0))
      extractCalleeName(call)
    check got == ""

  test "empty call (len < 1) returns empty":
    const got = static:
      let call = nnkCall.newTree()
      extractCalleeName(call)
    check got == ""
