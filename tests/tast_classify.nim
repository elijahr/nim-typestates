## Isolated unit tests for the PURE PNode classification helpers added to
## `ast_parser.nim` as the v0.9.4 AST-verifier building blocks:
## `collectRoutineDefs`, `peelToBaseTypeName`, `markerNameOf`,
## `classifyByPragma`, and `typestateParamBases`.
##
## These exercise the helpers in isolation on small in-memory snippets (parsed
## via `parseStringToPNode`, which reuses the same parse path as `parsePNode`).
## They do NOT go through `verify()` — that wiring is the next step.

import std/[unittest, sets, os]

import compiler/[ast, idents, options as compiler_options]

import ../src/typestates/ast_parser

proc parseOne(src: string): PNode =
  ## Parse a snippet to a top-level statement list.
  parseStringToPNode(src)

proc firstRoutine(src: string): PNode =
  ## Parse a snippet and return the first proc/func def found.
  var acc: seq[PNode]
  collectRoutineDefs(parseOne(src), acc)
  doAssert acc.len >= 1, "no routine found in snippet"
  acc[0]

proc paramTypeNode(procDef: PNode): PNode =
  ## Return the type node of the first parameter of a routine.
  let fp = procDef[paramsPos]
  doAssert fp.kind == nkFormalParams
  for child in fp:
    if child.kind == nkIdentDefs:
      return child[^2]
  doAssert false, "no nkIdentDefs param found"

suite "peelToBaseTypeName":
  template peelParam(src: string): string =
    peelToBaseTypeName(paramTypeNode(firstRoutine(src)))

  test "var generic -> base name":
    check peelParam("proc p(x: var PinnedScope[MT, CC]) = discard") == "PinnedScope"

  test "sink generic -> base name":
    check peelParam("proc p(x: sink RetireReady[MT, CC]) = discard") == "RetireReady"

  test "lent T -> peeled (edge-flag 2a)":
    check peelParam("proc p(x: lent Foo) = discard") == "Foo"

  test "ref T -> peeled":
    check peelParam("proc p(x: ref Open) = discard") == "Open"

  test "ptr T -> peeled":
    check peelParam("proc p(x: ptr Open) = discard") == "Open"

  test "var ptr T -> multi-peel (edge-flag 2c)":
    check peelParam("proc p(x: var ptr Open) = discard") == "Open"

  test "generic bracket -> head base":
    check peelParam("proc p(x: Stage1[T]) = discard") == "Stage1"

  test "plain ident -> itself":
    check peelParam("proc p(x: int) = discard") == "int"

  test "distinct alias used by name -> alias name, NOT underlying (edge-flag 2b)":
    # A named distinct alias arrives as an nkIdent (the alias name); we must
    # return the alias name, never transitively peel to its underlying base.
    let src = """
type
  Base = object
  MyAlias = distinct Base
proc p(x: MyAlias) = discard
"""
    check peelParam(src) == "MyAlias"

  test "bare inline distinct -> empty (never over-peel through distinct)":
    let src = "proc p(x: distinct Base) = discard"
    check peelToBaseTypeName(paramTypeNode(firstRoutine(src))) == ""

suite "classifyByPragma":
  template cls(src: string): ProcClass =
    classifyByPragma(firstRoutine(src))

  test "bare transition -> pcTransition":
    check cls("proc p(x: int) {.transition.} = discard") == pcTransition

  test "bare notATransition -> pcNotATransition":
    check cls("proc p(x: int) {.notATransition.} = discard") == pcNotATransition

  test "combined block with notATransition -> pcNotATransition (linchpin)":
    check cls("proc p(x: int): int {.discardable, raises: [], notATransition.} = 0") ==
      pcNotATransition

  test "combined block with transition -> pcTransition":
    check cls("proc p(x: int) {.raises: [], transition.} = discard") == pcTransition

  test "destructorTransition -> pcTransition":
    check cls("proc p(x: int) {.destructorTransition.} = discard") == pcTransition

  test "no pragma -> pcUnmarked":
    check cls("proc p(x: int) = discard") == pcUnmarked

  test "discardable only -> pcUnmarked":
    check cls("proc p(x: int): int {.discardable.} = 0") == pcUnmarked

suite "markerNameOf":
  proc pragmaChildren(src: string): seq[PNode] =
    let pragmaNode = firstRoutine(src)[pragmasPos]
    doAssert pragmaNode.kind == nkPragma
    for c in pragmaNode:
      result.add c

  test "bare ident child -> name":
    let kids = pragmaChildren("proc p(x: int) {.notATransition.} = discard")
    check markerNameOf(kids[0]) == "notATransition"

  test "ExprColonExpr child -> first-ident name":
    let kids = pragmaChildren("proc p(x: int) {.raises: [].} = discard")
    check markerNameOf(kids[0]) == "raises"

  test "combined block mixed children":
    let kids = pragmaChildren(
      "proc p(x: int): int {.discardable, raises: [], notATransition.} = 0"
    )
    check kids.len == 3
    check markerNameOf(kids[0]) == "discardable"
    check markerNameOf(kids[1]) == "raises"
    check markerNameOf(kids[2]) == "notATransition"

suite "collectRoutineDefs":
  proc nameOf(n: PNode): string =
    n[namePos].ident.s

  test "counts top-level procs":
    var acc: seq[PNode]
    collectRoutineDefs(parseOne("proc a() = discard\nproc b() = discard"), acc)
    check acc.len == 2

  test "descends into when true block":
    let src = """
proc a() = discard
when true:
  proc b() = discard
"""
    var acc: seq[PNode]
    collectRoutineDefs(parseOne(src), acc)
    check acc.len == 2

  test "excludes nested proc inside a body":
    let src = """
proc outer() =
  proc inner() = discard
  discard
"""
    var acc: seq[PNode]
    collectRoutineDefs(parseOne(src), acc)
    check acc.len == 1
    check nameOf(acc[0]) == "outer"

  test "excludes templates and converters":
    let src = """
proc a() = discard
template t() = discard
converter c(x: int): float = 0.0
func f() = discard
"""
    var acc: seq[PNode]
    collectRoutineDefs(parseOne(src), acc)
    check acc.len == 2 # a (proc) + f (func) only
    var names: seq[string]
    for n in acc:
      names.add nameOf(n)
    check "a" in names
    check "f" in names
    check "t" notin names
    check "c" notin names

suite "typestateParamBases":
  test "collects only registered base, grouped names share type":
    let procDef = firstRoutine("proc p(a: var Open, b: int) = discard")
    let registered = ["Open"].toHashSet
    check typestateParamBases(procDef, registered) == @["Open"]

  test "grouped param names share one type node -> one base":
    let procDef = firstRoutine("proc p(a, b: var Open) = discard")
    let registered = ["Open"].toHashSet
    check typestateParamBases(procDef, registered) == @["Open"]

  test "unregistered types excluded":
    let procDef = firstRoutine("proc p(a: int, b: string) = discard")
    let registered = ["Open"].toHashSet
    check typestateParamBases(procDef, registered).len == 0

suite "discriminative fixtures (helper-level)":
  ## Helper-level assertions for the two added discriminative fixtures. The
  ## full `verify()`-level integration assertions (in tests/tcli_verify_ast.nim)
  ## can only be made GREEN once the next step wires `classifyByPragma` /
  ## `typestateParamBases` into `verifyFile`. Until then we assert the building
  ## blocks behave correctly on the real fixture ASTs.
  const FixDir = "tests/fixtures/ast_verify"

  proc routinesOf(fixture: string): seq[PNode] =
    collectRoutineDefs(parsePNode(FixDir / fixture), result)

  proc byName(rs: seq[PNode], name: string): PNode =
    for r in rs:
      if r[namePos].kind == nkIdent and r[namePos].ident.s == name:
        return r
    doAssert false, "routine not found: " & name

  test "distinct_guard: Token param does NOT peel to a registered state (2b)":
    # TODO(next step): add a verify()-level assertion in tcli_verify_ast.nim
    # that distinct_guard.nim produces ZERO findings (no over-peel false flag).
    let routines = routinesOf("distinct_guard.nim")
    let registered = ["Open", "Closed"].toHashSet
    let useToken = byName(routines, "useToken")
    # The non-state distinct alias param must contribute NO registered base.
    check typestateParamBases(useToken, registered).len == 0
    # The genuine state proc is correctly seen as a typestate proc and marked.
    let seal = byName(routines, "seal")
    check typestateParamBases(seal, registered) == @["Open"]
    check classifyByPragma(seal) == pcTransition

  test "multipeel_var_ptr: var ptr <State> peels to the state base (2c)":
    # TODO(next step): add a verify()-level assertion in tcli_verify_ast.nim
    # that multipeel_var_ptr.nim produces ONE fcUnmarkedProcStrict error.
    let routines = routinesOf("multipeel_var_ptr.nim")
    let registered = ["Open", "Closed"].toHashSet
    let poke = byName(routines, "poke")
    # The multi-peel must reach the underlying state base.
    check typestateParamBases(poke, registered) == @["Open"]
    # And the proc is genuinely unmarked, so the integration step must flag it.
    check classifyByPragma(poke) == pcUnmarked
