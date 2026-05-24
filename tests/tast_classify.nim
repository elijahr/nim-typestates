## Isolated unit tests for the PURE PNode classification helpers added to
## `ast_parser.nim` as the v0.9.4 AST-verifier building blocks:
## `collectRoutineDefs`, `peelToBaseTypeName`, `markerNameOf`,
## `classifyByPragma`, and `typestateParamBases`.
##
## These exercise the helpers in isolation on small in-memory snippets (parsed
## via `parseStringToPNode`, which reuses the same parse path as `parsePNode`).
## They do NOT go through `verify()` — that wiring is the next step.

import std/[unittest, sets, os, strutils, tables]

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

  # `markerNameOf` returns the marker identifier NORMALIZED per Nim's rules
  # (`nimIdentNormalize`): first char preserved, rest lowercased, underscores
  # removed. The expected values below are the normalized canonical spellings.
  test "bare ident child -> name":
    let kids = pragmaChildren("proc p(x: int) {.notATransition.} = discard")
    check markerNameOf(kids[0]) == nimIdentNormalize("notATransition")

  test "ExprColonExpr child -> first-ident name":
    let kids = pragmaChildren("proc p(x: int) {.raises: [].} = discard")
    check markerNameOf(kids[0]) == nimIdentNormalize("raises")

  test "combined block mixed children":
    let kids = pragmaChildren(
      "proc p(x: int): int {.discardable, raises: [], notATransition.} = 0"
    )
    check kids.len == 3
    check markerNameOf(kids[0]) == nimIdentNormalize("discardable")
    check markerNameOf(kids[1]) == nimIdentNormalize("raises")
    check markerNameOf(kids[2]) == nimIdentNormalize("notATransition")

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

  test "descends into static block (FINDING 1)":
    # A routine wrapped in a module-level `static:` block was silently skipped
    # before the container-coverage widening.
    let src = """
static:
  proc s() = discard
"""
    var acc: seq[PNode]
    collectRoutineDefs(parseOne(src), acc)
    check acc.len == 1
    check nameOf(acc[0]) == "s"

  test "descends into block statement (FINDING 1)":
    let src = """
block:
  proc b() = discard
"""
    var acc: seq[PNode]
    collectRoutineDefs(parseOne(src), acc)
    check acc.len == 1
    check nameOf(acc[0]) == "b"

  test "descends into try/except/finally (FINDING 1)":
    let src = """
try:
  proc t() = discard
except:
  proc e() = discard
finally:
  proc f() = discard
"""
    var acc: seq[PNode]
    collectRoutineDefs(parseOne(src), acc)
    check acc.len == 3
    var names: seq[string]
    for n in acc:
      names.add nameOf(n)
    check "t" in names
    check "e" in names
    check "f" in names

  test "descends into if/else branches (FINDING 1)":
    let src = """
if true:
  proc i() = discard
else:
  proc el() = discard
"""
    var acc: seq[PNode]
    collectRoutineDefs(parseOne(src), acc)
    check acc.len == 2

  test "still excludes proc nested inside a body even when block-wrapped (FINDING 1)":
    # The widening must NOT start collecting genuinely nested routines: a proc
    # inside a `block:` that itself sits inside an outer proc body stays out of
    # scope because descent stops at the outer proc body.
    let src = """
proc outer() =
  block:
    proc inner() = discard
  discard
"""
    var acc: seq[PNode]
    collectRoutineDefs(parseOne(src), acc)
    check acc.len == 1
    check nameOf(acc[0]) == "outer"

  test "descends into block-pragma section (Gemini medium)":
    # A routine inside a `{.cast(gcsafe).}:` block parses as
    # `nkPragmaBlock -> nkStmtList -> proc`. Before adding `nkPragmaBlock` to
    # the container set it was silently skipped (RED proven empirically).
    let src = """
{.cast(gcsafe).}:
  proc bar() = discard
"""
    var acc: seq[PNode]
    collectRoutineDefs(parseOne(src), acc)
    check acc.len == 1
    check nameOf(acc[0]) == "bar"

  test "flat push/pop routine is collected via sibling walk (Gemini medium)":
    # The statement form `{.push.}` / `{.pop.}` parses as `nkPragma` SIBLINGS of
    # the routine in the surrounding `nkStmtList`; the routine is therefore
    # already collected by the normal sibling walk, with NO `nkPragma` handling.
    let src = """
{.push raises: [].}
proc foo() = discard
{.pop.}
"""
    var acc: seq[PNode]
    collectRoutineDefs(parseOne(src), acc)
    check acc.len == 1
    check nameOf(acc[0]) == "foo"

  test "descends into case/of/else branches (Gemini medium)":
    # `case`/`of`/`else` branches wrap routines in an inner `nkStmtList`, but the
    # `nkCaseStmt`/`nkOfBranch` nodes themselves must be descended to reach it.
    # Before adding them, routines in a `case` were silently skipped.
    let src = """
case 1
of 1:
  proc c1() = discard
else:
  proc c2() = discard
"""
    var acc: seq[PNode]
    collectRoutineDefs(parseOne(src), acc)
    check acc.len == 2
    var names: seq[string]
    for n in acc:
      names.add nameOf(n)
    check "c1" in names
    check "c2" in names

  test "still excludes proc nested inside a body when block-pragma-wrapped (Gemini medium)":
    # Scoping invariant for the new `nkPragmaBlock` descent: a routine inside a
    # block-pragma section that itself sits inside an outer proc body stays out
    # of scope because descent stops at the outer proc body.
    let src = """
proc outer() =
  {.cast(gcsafe).}:
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

suite "style-insensitivity (Nim identifier rules)":
  ## Nim identifiers are style-insensitive: the FIRST character is
  ## case-sensitive; the rest are case-insensitive AND underscores are ignored.
  ## The AST helpers must normalize identifiers consistently with the
  ## registration side so style variants of a state name / pragma marker match,
  ## while a first-letter-case difference (a genuinely distinct identifier) does
  ## NOT match.

  test "typestateParamBases: My_State matches registered MyState":
    # `My_State` == `MyState` (same first letter, underscore ignored, rest
    # case-folded), so it must resolve to the registered base. The registered
    # set is normalized exactly as the production registration side does.
    let procDef = firstRoutine("proc p(s: var My_State) = discard")
    let registered = [nimIdentNormalize("MyState")].toHashSet
    # The returned base preserves the param's own readable spelling.
    check typestateParamBases(procDef, registered) == @["My_State"]

  test "typestateParamBases: first-letter-case difference does NOT match":
    # `my_state` differs from `MyState` in the first letter (`m` vs `M`); under
    # Nim's rules these are DISTINCT identifiers and must not match.
    let procDef = firstRoutine("proc p(s: var my_state) = discard")
    let registered = [nimIdentNormalize("MyState")].toHashSet
    check typestateParamBases(procDef, registered).len == 0

  test "classifyByPragma: style-variant notATransition marker recognized":
    # `not_a_transition` is the same marker as `notATransition`.
    check classifyByPragma(
      firstRoutine("proc p(x: int) {.not_a_transition.} = discard")
    ) == pcNotATransition

  test "markerNameOf: style-variant marker normalizes to canonical form":
    let pragmaNode =
      firstRoutine("proc p(x: int) {.not_a_transition.} = discard")[pragmasPos]
    doAssert pragmaNode.kind == nkPragma
    # The returned marker name must compare equal to the canonical marker after
    # normalization. We assert the normalized form directly here.
    check nimIdentNormalize(markerNameOf(pragmaNode[0])) ==
      nimIdentNormalize("notATransition")

suite "nkAccQuoted routine names":
  ## Backticked / operator routine names parse as `nkAccQuoted`. The routine
  ## name extractor must render them to a sensible symbol, not an empty string.

  test "classifyProcsInFile: operator routine carries a non-empty name":
    let src = """
proc `[]`(s: var Open; i: int) = discard
"""
    let registered = ["Open"].toHashSet
    let classified = classifyProcsInFile(parseOne(src), registered)
    check classified.len == 1
    check classified[0].name.len > 0
    check "[]" in classified[0].name

  test "classifyProcsInFile: == operator routine carries a sensible name":
    let src = """
proc `==`(a, b: Open): bool = true
"""
    let registered = ["Open"].toHashSet
    let classified = classifyProcsInFile(parseOne(src), registered)
    check classified.len == 1
    check "==" in classified[0].name

  test "classifyProcsInFile: EXPORTED operator routine carries a non-empty name":
    # Exported backticked names parse as `nkPostfix[nkIdent("*"), nkAccQuoted]`.
    # The name extractor must peel the `nkPostfix` AND render the nested
    # `nkAccQuoted`, not stop at the postfix and yield an empty/anonymous name.
    let src = """
proc `[]`*(s: var Open; i: int) = discard
"""
    let registered = ["Open"].toHashSet
    let classified = classifyProcsInFile(parseOne(src), registered)
    check classified.len == 1
    check classified[0].name.len > 0
    check "[]" in classified[0].name

  test "classifyProcsInFile: EXPORTED == operator routine carries a sensible name":
    let src = """
proc `==`*(a, b: Open): bool = true
"""
    let registered = ["Open"].toHashSet
    let classified = classifyProcsInFile(parseOne(src), registered)
    check classified.len == 1
    check classified[0].name.len > 0
    check "==" in classified[0].name

suite "deterministic node iteration order":
  ## `ParsedProject.nodes` is an `OrderedTable`, so iterating it follows the
  ## order paths were processed (insertion order), not hash order. This makes
  ## the verify finding report order deterministic across runs for the same
  ## inputs.
  const FixDir = "tests/fixtures/ast_verify"

  test "nodes iteration order equals explicit path argument order":
    # An explicit `.nim` path list is processed in argument order, so the
    # `nodes` keys must come out in exactly that order.
    let paths = @[
      FixDir / "operator_routine.nim",
      FixDir / "non_exported.nim",
      FixDir / "overloaded.nim",
      FixDir / "ref_ptr_param.nim",
      FixDir / "comment_literal.nim",
    ]
    let project = parseTypestatesAstWithNodes(paths)
    var encountered: seq[string]
    for filePath, _ in project.nodes:
      encountered.add filePath
    check encountered == paths

  test "nodes iteration order is stable across repeated parses":
    # Same inputs -> same iteration order on every run (the property that fixes
    # non-deterministic finding report order).
    let paths = @[
      FixDir / "overloaded.nim",
      FixDir / "operator_routine.nim",
      FixDir / "comment_literal.nim",
      FixDir / "non_exported.nim",
    ]
    var firstOrder: seq[string]
    for filePath, _ in parseTypestatesAstWithNodes(paths).nodes:
      firstOrder.add filePath
    var secondOrder: seq[string]
    for filePath, _ in parseTypestatesAstWithNodes(paths).nodes:
      secondOrder.add filePath
    check firstOrder == paths
    check secondOrder == paths

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
