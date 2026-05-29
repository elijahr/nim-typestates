## Test (Gemini round-2 Finding 1): the `{.transition.}` macro's
## idempotency check for `TypestateOp` in an existing `{.tags: [...].}`
## list must recognize module-qualified (`pragmas.TypestateOp`,
## `nnkDotExpr`) and backtick-quoted (`` `TypestateOp` ``,
## `nnkAccQuoted`) entries, not only bare `nnkIdent`/`nnkSym`.
##
## Bug history: pre-fix the check used `eqIdent` on entries restricted
## to `{nnkIdent, nnkSym}`. A user who wrote
## `{.tags: [pragmas.TypestateOp].}` (DotExpr) or
## `{.tags: [`TypestateOp`].}` (AccQuoted) bypassed the dedup, so the
## macro appended a SECOND `TypestateOp` entry to the same bracket.
## Behavior was still correct (Nim de-duplicates at the effect-set
## level) but the AST carried a redundant node. The fix widens the
## check to compare the rightmost identifier of `nnkDotExpr` and the
## inner ident of `nnkAccQuoted`.
##
## This test introspects the post-macro pragma AST of two transition
## procs (one with DotExpr, one with AccQuoted) and asserts the
## `tags:` bracket contains exactly ONE `TypestateOp`-shaped entry.
{.experimental: "strictEffects".}
import std/[macros, unittest]
import ../src/typestates
import ../src/typestates/pragmas as pragmasMod

type
  EndpointBase = object
  Unbound = distinct EndpointBase
  Bound = distinct EndpointBase

typestate Endpoint:
  consumeOnTransition = false
  strictTransitions = false
  states Unbound, Bound
  transitions:
    Unbound -> Bound

# Qualified form. Pre-fix: macro fails to detect `pragmasMod.TypestateOp`
# as TypestateOp and appends a duplicate `TypestateOp` to the same
# bracket.
proc bindQualified(u: Unbound): Bound
    {.transition, tags: [pragmasMod.TypestateOp, RootEffect].} =
  Bound(EndpointBase(u))

# AccQuoted form. Pre-fix: macro fails to detect `` `TypestateOp` ``
# as TypestateOp and appends a duplicate.
proc bindAccQuoted(u: Unbound): Bound
    {.transition, tags: [`TypestateOp`, RootEffect].} =
  Bound(EndpointBase(u))

verifyTypestates()

# Count how many entries inside the `tags:` bracket of `procSym`'s
# implementation resolve (by rightmost-ident comparison) to
# `TypestateOp`. Returns -1 if no `tags:` pragma is found, so the test
# can distinguish "missing tags" from "duplicate tags".
macro countTypestateOpInTags(procSym: typed): int =
  var sym = procSym
  if sym.kind == nnkClosedSymChoice or sym.kind == nnkOpenSymChoice:
    sym = sym[0]
  let impl = sym.getImpl()
  expectKind(impl, {nnkProcDef, nnkFuncDef, nnkConverterDef})
  let pragmas = impl.pragma
  var bracket: NimNode = nil
  for child in pragmas:
    case child.kind
    of nnkExprColonExpr:
      if child[0].kind in {nnkIdent, nnkSym} and child[0].eqIdent("tags") and
          child[1].kind == nnkBracket:
        bracket = child[1]
        break
    of nnkCall:
      if child[0].kind in {nnkIdent, nnkSym} and child[0].eqIdent("tags") and
          child.len > 1 and child[1].kind == nnkBracket:
        bracket = child[1]
        break
    else:
      discard
  if bracket == nil:
    return newLit(-1)
  var count = 0
  for entry in bracket:
    case entry.kind
    of nnkIdent, nnkSym:
      if entry.eqIdent("TypestateOp"):
        inc count
    of nnkDotExpr:
      # Rightmost component is the actual identifier.
      let rhs = entry[^1]
      if rhs.kind in {nnkIdent, nnkSym} and rhs.eqIdent("TypestateOp"):
        inc count
    of nnkAccQuoted:
      if entry.len >= 1 and entry[0].kind in {nnkIdent, nnkSym} and
          entry[0].eqIdent("TypestateOp"):
        inc count
    else:
      discard
  newLit(count)

suite "TypestateOp idempotency on qualified and AccQuoted forms":
  test "module-qualified TypestateOp is not duplicated":
    check countTypestateOpInTags(bindQualified) == 1

  test "AccQuoted `TypestateOp` is not duplicated":
    check countTypestateOpInTags(bindAccQuoted) == 1
