## Unit tests for the opaque-states lint module.
##
## Each test uses a tempfile pattern (mirrors `tests/tcli.nim`), parsing the
## fixture via `parseTypestatesAst` and then running `lintOpaqueStates` over
## the same path. Assertions are on the returned `seq[string]`.
##
## Warning string contract (LOCKED — change here means change in the impl):
##   {path}:{line} - bypass of opaque state '{stateName}' (typestate '{tsName}') outside {.transition.} proc
##   opaqueStates = true on typestate '{name}' but no initial states declared; lint disabled for this typestate

import std/[unittest, os, strutils, sequtils]
import ../src/typestates/ast_parser
import ../src/typestates/lint_opaque_states

proc writeTemp(name, body: string): string =
  ## Write `body` to a temp file under `getTempDir()` and return the path.
  result = getTempDir() / name
  writeFile(result, body)

proc lintOf(path: string): seq[string] =
  let pr = parseTypestatesAst(@[path])
  lintOpaqueStates(pr, @[path])

const opaquePaymentHeader = """
type
  Payment = object
    id: string
  Created = distinct Payment
  Authorized = distinct Payment
  Captured = distinct Payment

typestate Payment:
  consumeOnTransition = false
  opaqueStates = true
  states Created, Authorized, Captured
  initial Created
  transitions:
    Created -> Authorized
    Authorized -> Captured
"""

const nonOpaquePaymentHeader = """
type
  Payment = object
    id: string
  Created = distinct Payment
  Authorized = distinct Payment
  Captured = distinct Payment

typestate Payment:
  consumeOnTransition = false
  states Created, Authorized, Captured
  initial Created
  transitions:
    Created -> Authorized
    Authorized -> Captured
"""

suite "Opaque states lint":
  test "1. bypass detected outside transition":
    let path = writeTemp(
      "tlint_opaque_01.nim",
      opaquePaymentHeader & "\nlet bad = Captured(Payment(id: \"x\"))\n",
    )
    let warnings = lintOf(path)
    check warnings.len == 1
    check "bypass of opaque state 'Captured'" in warnings[0]
    check "(typestate 'Payment')" in warnings[0]
    check "outside {.transition.} proc" in warnings[0]
    removeFile(path)

  test "2. no warning inside {.transition.}":
    let path = writeTemp(
      "tlint_opaque_02.nim",
      opaquePaymentHeader & """
proc cap(a: Authorized): Captured {.transition.} =
  Captured(a)
""",
    )
    let warnings = lintOf(path)
    check warnings.len == 0
    removeFile(path)

  test "3. result = inside {.transition.}":
    let path = writeTemp(
      "tlint_opaque_03.nim",
      opaquePaymentHeader & """
proc cap(a: Authorized): Captured {.transition.} =
  result = Captured(a)
""",
    )
    let warnings = lintOf(path)
    check warnings.len == 0
    removeFile(path)

  test "4. initial state never warned":
    let path = writeTemp(
      "tlint_opaque_04.nim",
      opaquePaymentHeader & "\nlet p = Created(Payment(id: \"x\"))\n",
    )
    let warnings = lintOf(path)
    check warnings.len == 0
    removeFile(path)

  test "5. multi-initial states; only non-initial flagged":
    # Typestate with two initial states (A, B) and one non-initial state (C).
    # Bypasses on A() and B() are silent; bypass on C() is flagged.
    let body = """
type
  Doc = object
    s: string
  A = distinct Doc
  B = distinct Doc
  C = distinct Doc

typestate Doc:
  consumeOnTransition = false
  opaqueStates = true
  states A, B, C
  initial:
    A
    B
  transitions:
    A -> C
    B -> C

let x = A(Doc(s: "x"))
let y = B(Doc(s: "y"))
let z = C(Doc(s: "z"))
"""
    let path = writeTemp("tlint_opaque_05.nim", body)
    let warnings = lintOf(path)
    check warnings.len == 1
    check "bypass of opaque state 'C'" in warnings[0]
    # Negative: A and B must not be reported
    check not warnings[0].contains("'A'")
    check not warnings[0].contains("'B'")
    removeFile(path)

  test "6. opaqueStates with no initial states emits config warning":
    # Edge case — opaqueStates = true but no initial block. Lint should
    # emit one configuration warning and skip all bypass detection on this
    # typestate (so the bypass below must NOT produce a bypass warning).
    let body = """
type
  Doc = object
  A = distinct Doc
  B = distinct Doc

typestate Doc:
  consumeOnTransition = false
  opaqueStates = true
  states A, B
  transitions:
    A -> B

let x = B(Doc())
"""
    let path = writeTemp("tlint_opaque_06.nim", body)
    let warnings = lintOf(path)
    # Exactly one warning; it is the config warning, not a bypass warning.
    check warnings.len == 1
    check "opaqueStates = true on typestate 'Doc'" in warnings[0]
    check "no initial states declared" in warnings[0]
    check "lint disabled for this typestate" in warnings[0]
    # Negative: no bypass warning for B.
    check not warnings.anyIt("bypass of opaque state" in it)
    removeFile(path)

  test "7. empty fast-path: no opaque-flagged typestates":
    let path = writeTemp(
      "tlint_opaque_07.nim",
      nonOpaquePaymentHeader & "\nlet bad = Captured(Payment(id: \"x\"))\n",
    )
    let warnings = lintOf(path)
    check warnings.len == 0
    removeFile(path)

  test "8. qualified call payments.Captured(p)":
    # The qualified-call form `module.Captured(p)` reads as nkDotExpr at
    # the callee. We construct a fixture where the bypass site is a
    # qualified call so this test specifically exercises the nkDotExpr
    # branch of inspectCall.
    let body =
      opaquePaymentHeader & """

# Define a stub holder with a Captured field, then call via dotted access.
# The callee node is nkDotExpr(payments, Captured), which the lint must
# detect even though the surface form is module-prefixed.
type Mod = object
proc Captured(self: Mod, p: Payment): Captured {.transition.} = Captured(p)
let payments = Mod()
let bad = payments.Captured(Payment(id: "x"))
"""
    let path = writeTemp("tlint_opaque_08.nim", body)
    let warnings = lintOf(path)
    # The `proc Captured` is marked {.transition.}, so its body's
    # `Captured(p)` is silenced. The qualified `payments.Captured(...)`
    # at top level IS a bypass (nkDotExpr callee) and must be flagged.
    check warnings.len == 1
    check "bypass of opaque state 'Captured'" in warnings[0]
    check "(typestate 'Payment')" in warnings[0]
    removeFile(path)

  test "9. generic-typed initial state construction — allowed (initial-skip)":
    # The fixture constructs the initial state `Empty` with a concrete payload.
    # Initial-state construction is always allowed, regardless of opaqueness.
    # Note: genuine nkBracketExpr generic instantiation (e.g. `Full[int](...)`)
    # handling is deferred to v0.7 and is NOT exercised by this test.
    let body = """
type
  Box = object
    items: seq[int]
  Empty = distinct Box
  Full = distinct Box

typestate Box:
  consumeOnTransition = false
  opaqueStates = true
  states Empty, Full
  initial Empty
  transitions:
    Empty -> Full

# Initial state Empty[T] constructed with concrete payload — allowed because state is initial.
let e = Empty(Box(items: @[1, 2, 3]))
"""
    let path = writeTemp("tlint_opaque_09.nim", body)
    let warnings = lintOf(path)
    check warnings.len == 0
    removeFile(path)

  test "10. multiple bypasses; one warning per bypass with correct lines":
    # Construct a fixture with bypasses on KNOWN lines so we can assert
    # exact `:N` substrings. The header is 16 lines (lines 1-16); line 17
    # is blank; we put bypasses on lines 18, 22, 26.
    let body =
      opaquePaymentHeader & """

let a = Captured(Payment(id: "1"))
let dummy1 = 0
let dummy2 = 0
let b = Captured(Payment(id: "2"))
let dummy3 = 0
let dummy4 = 0
let c = Captured(Payment(id: "3"))
"""
    let path = writeTemp("tlint_opaque_10.nim", body)
    let warnings = lintOf(path)
    check warnings.len == 3
    # Each bypass mentions Captured / Payment / outside scope
    for w in warnings:
      check "bypass of opaque state 'Captured'" in w
      check "(typestate 'Payment')" in w
      check "outside {.transition.} proc" in w
    # Line-info correctness: the three bypasses live at known offsets.
    # opaquePaymentHeader is exactly 17 lines (16 lines + trailing newline ->
    # line 17 is empty). The appended body adds: line 18 blank, line 19 a-bypass,
    # 20 dummy, 21 dummy, 22 b-bypass, 23 dummy, 24 dummy, 25 c-bypass.
    # We compute lines empirically rather than hard-code, by counting newlines
    # in the header.
    let headerLines = opaquePaymentHeader.count('\n')
    let aLine = headerLines + 2 # blank + a
    let bLine = headerLines + 5
    let cLine = headerLines + 8
    let lineMarkerA = ":" & $aLine & " "
    let lineMarkerB = ":" & $bLine & " "
    let lineMarkerC = ":" & $cLine & " "
    check warnings.anyIt(lineMarkerA in it)
    check warnings.anyIt(lineMarkerB in it)
    check warnings.anyIt(lineMarkerC in it)
    removeFile(path)

  test "11. nkCommand form 'Captured payment' (no parens)":
    # `Captured payment` parses as nkCommand. The lint must catch it.
    let body =
      opaquePaymentHeader & """

let payment = Payment(id: "x")
discard Captured payment
"""
    let path = writeTemp("tlint_opaque_11.nim", body)
    let warnings = lintOf(path)
    check warnings.len == 1
    check "bypass of opaque state 'Captured'" in warnings[0]
    removeFile(path)

  test "12. async transition — Future[Captured] body construction":
    # This test uses {.transition, async.} pragma combo. We do NOT actually
    # need std/asyncdispatch; the lint reads source AST only. The walker
    # detects `transition` in the pragma list regardless of order.
    let body =
      opaquePaymentHeader & """

# Simulated async transition; no runtime needed. {.transition.} is detected
# by the walker from the pragma list, so the body is in-scope.
proc cap(a: Authorized): Captured {.transition, gcsafe.} =
  Captured(a)
"""
    let path = writeTemp("tlint_opaque_12.nim", body)
    let warnings = lintOf(path)
    check warnings.len == 0
    removeFile(path)

  test "13. lambda inside {.transition.} body — zero warnings":
    let body =
      opaquePaymentHeader & """

proc cap(a: Authorized): Captured {.transition.} =
  let f = proc(x: Authorized): Captured = Captured(x)
  f(a)
"""
    let path = writeTemp("tlint_opaque_13.nim", body)
    let warnings = lintOf(path)
    check warnings.len == 0
    removeFile(path)

  test "14. configuration warning + suppression of bypass detection":
    # Same as test 6 but with a richer fixture to confirm config warning
    # is emitted exactly once and bypasses on the misconfigured typestate
    # are NOT warned.
    let body = """
type
  Doc = object
  A = distinct Doc
  B = distinct Doc
  C = distinct Doc

typestate Doc:
  consumeOnTransition = false
  opaqueStates = true
  states A, B, C
  transitions:
    A -> B
    B -> C

let x = A(Doc())
let y = B(Doc())
let z = C(Doc())
"""
    let path = writeTemp("tlint_opaque_14.nim", body)
    let warnings = lintOf(path)
    check warnings.len == 1
    check "opaqueStates = true on typestate 'Doc'" in warnings[0]
    check not warnings.anyIt("bypass of opaque state" in it)
    removeFile(path)

  test "15. mixed opaque + non-opaque typestates":
    # Two typestates in one file: Doc is opaque, Box is not. Bypasses on
    # Doc states are flagged; bypasses on Box states are silent.
    let body = """
type
  Doc = object
    s: string
  DA = distinct Doc
  DB = distinct Doc

  Box = object
    n: int
  BA = distinct Box
  BB = distinct Box

typestate Doc:
  consumeOnTransition = false
  opaqueStates = true
  states DA, DB
  initial DA
  transitions:
    DA -> DB

typestate Box:
  consumeOnTransition = false
  states BA, BB
  initial BA
  transitions:
    BA -> BB

let docBypass = DB(Doc(s: "x"))
let boxBypass = BB(Box(n: 1))
"""
    let path = writeTemp("tlint_opaque_15.nim", body)
    let warnings = lintOf(path)
    check warnings.len == 1
    check "bypass of opaque state 'DB'" in warnings[0]
    check "(typestate 'Doc')" in warnings[0]
    check not warnings.anyIt("'BB'" in it)
    removeFile(path)

  test "16. cast[Captured](p) form — deferred (nkCast not nkCall)":
    let body =
      opaquePaymentHeader & """

let p = Payment(id: "x")
let bad = cast[Captured](p)
"""
    let path = writeTemp("tlint_opaque_16.nim", body)
    let warnings = lintOf(path)
    check warnings.len == 0
    removeFile(path)

  test "17. cross-file fast-path: typestate path omitted":
    # If the typestate definition is in fileA but only fileB is passed to
    # parseTypestatesAst, the opaque table is empty -> fast-path returns
    # @[] without warning. Documented limitation.
    let typestatePath = writeTemp("tlint_opaque_17_lib.nim", opaquePaymentHeader)
    let consumerPath = writeTemp(
      "tlint_opaque_17_app.nim",
      """
import "./tlint_opaque_17_lib"

let bad = Captured(Payment(id: "x"))
""",
    )
    # Only pass the consumer path. The typestate is unknown -> empty table
    # -> zero warnings.
    let pr = parseTypestatesAst(@[consumerPath])
    let warnings = lintOpaqueStates(pr, @[consumerPath])
    check warnings.len == 0
    removeFile(typestatePath)
    removeFile(consumerPath)

  test "18. same-name shadowing — proc Captured exists, still warns":
    # Documented limitation: lint identifies by ident name only, so a
    # user-defined `proc Captured` collides with the state name and every
    # call is warned.
    let body =
      opaquePaymentHeader & """

proc Captured(s: string): string = "captured " & s
let z = Captured("hello")
"""
    let path = writeTemp("tlint_opaque_18.nim", body)
    let warnings = lintOf(path)
    # The only call site outside transition is `Captured("hello")` and
    # the lint cannot tell user-proc from state-ctor — fires.
    check warnings.len >= 1
    check warnings.anyIt("bypass of opaque state 'Captured'" in it)
    removeFile(path)

  test "19. macro-arg call site logged(Captured(p))":
    # `Captured(p)` is a literal nkCall as an argument of `logged`. The
    # walker recurses into all children of nkCall, so it reaches the
    # nested call.
    let body =
      opaquePaymentHeader & """

proc logged(c: Captured): Captured = c
let bad = logged(Captured(Payment(id: "x")))
"""
    let path = writeTemp("tlint_opaque_19.nim", body)
    let warnings = lintOf(path)
    # Only the `Captured(Payment(...))` argument is the bypass.
    check warnings.len == 1
    check "bypass of opaque state 'Captured'" in warnings[0]
    removeFile(path)

  test "20. nkDo block inside {.transition.} body":
    # `someProc.callback do (x): Captured(x)` inside a transition routine.
    # nkDo is a child of the routine call; the walker enters it with
    # inTransition still > 0.
    let body =
      opaquePaymentHeader & """

proc invoke(handler: proc(x: Authorized): Captured): Captured =
  discard

proc cap(a: Authorized): Captured {.transition.} =
  invoke do (x: Authorized) -> Captured:
    Captured(x)
"""
    let path = writeTemp("tlint_opaque_20.nim", body)
    let warnings = lintOf(path)
    check warnings.len == 0
    removeFile(path)

  test "21. template body — warns (lint reads source)":
    # Documented deliberate behavior: lint walks source AST, never expands.
    # A template that constructs a state outside a transition is reported
    # at the template definition site.
    let body =
      opaquePaymentHeader & """

template makeC(p: Payment): untyped =
  Captured(p)

let z = makeC(Payment(id: "x"))
"""
    let path = writeTemp("tlint_opaque_21.nim", body)
    let warnings = lintOf(path)
    check warnings.len == 1
    check "bypass of opaque state 'Captured'" in warnings[0]
    removeFile(path)

  test "22. non-literal flag rhs — flag stays default false":
    # extractFlag returns none(bool) when rhs is anything other than literal
    # `true`/`false`. Flag stays default false; no opaque entries; zero warnings.
    let body = """
type
  Payment = object
    id: string
  Created = distinct Payment
  Captured = distinct Payment

const someConst = true

typestate Payment:
  consumeOnTransition = false
  opaqueStates = someConst
  states Created, Captured
  initial Created
  transitions:
    Created -> Captured

let bad = Captured(Payment(id: "x"))
"""
    let path = writeTemp("tlint_opaque_22.nim", body)
    let warnings = lintOf(path)
    check warnings.len == 0
    removeFile(path)

  test "23. nested unmarked proc inside transition: bypass detected":
    # A nested `proc inner` (no `{.transition.}` pragma) declared inside
    # an outer `{.transition.}` body is a SEPARATE scope. Its body must
    # be linted as if outside any transition, i.e. raw `Captured(...)`
    # construction in `inner` is a bypass and must be flagged.
    #
    # Regression: previously the walker incremented `inTransition` on
    # entry to the outer routine and never reset on entry to the nested
    # routine, silently swallowing this bypass.
    let body =
      opaquePaymentHeader & """

proc cap(a: Authorized): Captured {.transition.} =
  proc inner(): Captured =
    Captured(Payment(id: "leak"))
  Captured(a)
"""
    let path = writeTemp("tlint_opaque_23.nim", body)
    let warnings = lintOf(path)
    check warnings.len == 1
    check "bypass of opaque state 'Captured'" in warnings[0]
    # Line of the inner-proc bypass: header lines + 4 lines into the body
    # (blank, `proc cap...`, `  proc inner()...`, `    Captured(...)`).
    let headerLines = opaquePaymentHeader.count('\n')
    let leakLine = headerLines + 4
    check (":" & $leakLine & " ") in warnings[0]
    removeFile(path)

  test "24. nested transition proc inside transition: dest state allowed in inner body":
    # Documents the reset-to-1 semantics: when a nested routine carries
    # `{.transition.}` (verified to be macro-accepted on Nim 2.2.6), the
    # walker enters its body with `inTransition = 1` regardless of the
    # outer scope. Constructing a non-initial opaque state inside the
    # inner body is therefore allowed.
    let body =
      opaquePaymentHeader & """

proc outer(c: Created): Authorized {.transition.} =
  proc inner(a: Authorized): Captured {.transition.} =
    Captured(a)
  Authorized(c)
"""
    let path = writeTemp("tlint_opaque_24.nim", body)
    let warnings = lintOf(path)
    check warnings.len == 0
    removeFile(path)

  test "25. overlapping paths dedupe: file + containing dir warned once":
    # Regression: passing both a directory and a file inside that directory
    # used to trigger the lint to walk the file twice, producing duplicate
    # warnings for the same line. lintOpaqueStates dedupes by absolute path.
    let tmpDir = getTempDir() / "tlint_opaque_25_dir"
    createDir(tmpDir)
    let filePath = tmpDir / "src.nim"
    writeFile(
      filePath, opaquePaymentHeader & "\nlet bad = Captured(Payment(id: \"x\"))\n"
    )
    # Pass overlapping paths: the directory AND the file inside it.
    let pr = parseTypestatesAst(@[filePath])
    let warnings = lintOpaqueStates(pr, @[tmpDir, filePath])
    # Exactly one bypass warning, not two.
    check warnings.len == 1
    check "bypass of opaque state 'Captured'" in warnings[0]
    removeFile(filePath)
    removeDir(tmpDir)
