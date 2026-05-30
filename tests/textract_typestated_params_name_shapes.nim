## Structural unit tests for `extractTypestatedParams` param-name unwrap
## (pragmas.nim:304).
##
## Round-16 GEM-MEDIUM acceptance test: exercises every param-name AST
## shape the macro layer might see at registration time, including the
## defensive nested `nnkPostfix`-inside-`nnkPragmaExpr` shape that user
## source cannot produce directly (Nim's parser rejects `p* {.x.}: T`)
## but a downstream macro that hand-builds a procDef AST might emit.
## Pre-round-16 the param-name extractor's `nnkPragmaExpr` branch
## inspected only `[0].kind in {Ident, Sym}`, so the nested-Postfix
## case skipped the param entry entirely.
##
## Each test hand-builds a minimal procDef AST matching one shape,
## passes it to `extractTypestatedParams`, and asserts the recovered
## name. The source state type `LU_Open` is registered via the
## `typestate` macro at module scope so `findTypestateForState` resolves
## and the param is not skipped on the non-typestate-bearing fallback.
##
## Mirrors the round-15 `textract_type_decl_name.nim` pattern.

import std/unittest
import std/macros

import ../src/typestates

# Register the typestate graph at module scope so the compile-time
# registry is populated before the static blocks below run.
type
  LU_Pipe = object
    fd: int

  LU_Open = distinct LU_Pipe
  LU_Closed = distinct LU_Pipe

typestate LU_PipeContext:
  consumeOnTransition = false
  strictTransitions = false
  states LU_Open, LU_Closed
  initial:
    LU_Open
  terminal:
    LU_Closed
  transitions:
    LU_Open -> LU_Closed

# `extractTypestatedParams` is `{.compileTime.}`. Build the procDef AST,
# invoke the extractor inside `static:`, and surface the captured name
# via a `const`.

template buildBareProc(paramName: NimNode): NimNode =
  # proc f(<paramName>: var LU_Open): LU_Closed
  nnkProcDef.newTree(
    ident("f"),
    newEmptyNode(),
    newEmptyNode(),
    nnkFormalParams.newTree(
      ident("LU_Closed"),
      nnkIdentDefs.newTree(
        paramName, nnkVarTy.newTree(ident("LU_Open")), newEmptyNode()
      ),
    ),
    newEmptyNode(),
    newEmptyNode(),
    nnkStmtList.newTree(newEmptyNode()),
  )

suite "extractTypestatedParams param-name shape recognizer":
  test "bare ident: `proc f(p: var LU_Open): LU_Closed`":
    const got = static:
      let procDef = buildBareProc(ident("p"))
      let params = extractTypestatedParams(procDef)
      doAssert params.len == 1
      params[0].name
    check got == "p"

  test "postfix `p*`":
    const got = static:
      let postfix = nnkPostfix.newTree(ident("*"), ident("p"))
      let procDef = buildBareProc(postfix)
      let params = extractTypestatedParams(procDef)
      doAssert params.len == 1
      params[0].name
    check got == "p"

  test "pragma-decorated `p {.x.}`":
    const got = static:
      let pragmaExpr =
        nnkPragmaExpr.newTree(ident("p"), nnkPragma.newTree(ident("noopUser")))
      let procDef = buildBareProc(pragmaExpr)
      let params = extractTypestatedParams(procDef)
      doAssert params.len == 1
      params[0].name
    check got == "p"

  test "nested postfix-in-pragmaExpr `PragmaExpr(Postfix(*, p), Pragma)` — GEM-MEDIUM":
    ## Defensive shape: Nim's parser rejects `p* {.x.}: T` at parse
    ## time, but a hand-built procDef from a downstream macro can
    ## emit this AST. Pre-round-16 the param-name extractor's
    ## PragmaExpr branch checked `[0].kind in {Ident, Sym}`, found
    ## `nnkPostfix`, and skipped the param. Post-round-16 the
    ## unwrap precedence (PragmaExpr -> Postfix -> leaf) recovers
    ## `"p"` correctly.
    const got = static:
      let postfix = nnkPostfix.newTree(ident("*"), ident("p"))
      let pragmaExpr =
        nnkPragmaExpr.newTree(postfix, nnkPragma.newTree(ident("noopUser")))
      let procDef = buildBareProc(pragmaExpr)
      let params = extractTypestatedParams(procDef)
      doAssert params.len == 1
      params[0].name
    check got == "p"

  test "AccQuoted-in-pragmaExpr ``PragmaExpr(AccQuoted(`p`), Pragma)``":
    ## User-reachable shape: `proc f(\`p\` {.x.}: var LU_Open)` parses
    ## as `PragmaExpr(AccQuoted(Ident), Pragma)`. The unwrap drops
    ## to the leaf AccQuoted and the case-dispatch reassembles
    ## the backticked name.
    const got = static:
      let accQ = nnkAccQuoted.newTree(ident("p"))
      let pragmaExpr = nnkPragmaExpr.newTree(accQ, nnkPragma.newTree(ident("noopUser")))
      let procDef = buildBareProc(pragmaExpr)
      let params = extractTypestatedParams(procDef)
      doAssert params.len == 1
      params[0].name
    check got == "p"
