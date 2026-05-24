## Regression (PR #13 review "F4a"): the TRUE single-line `defaults:` body form,
## `defaults: CC: ccSingle`, parses to the SAME `nnkStmtList`-bodied AST as the
## multi-line indented form (covered by `defaults_section_simple.nim`). So
## `parseDefaultsBlock`'s body-finder locates the `nnkStmtList` child and the
## `nnkCall` entry branch handles the `CC: ccSingle` entry. The claim that the
## single-line form yields a bare `nnkExprColonExpr` directly under the `defaults`
## call (leaving `body` nil and erroring) is false.
##
## Why a string literal instead of a literal single-line fixture: `nph` normalizes
## the single-line `defaults: CC: ccSingle` into the multi-line indented form, so a
## literal single-line fixture cannot survive the formatter (it would become
## byte-identical to `defaults_section_simple.nim` and stop exercising the
## single-line path). Holding the single-line text in a string literal keeps the
## discriminative form intact — `nph` does not rewrite string contents — and lets
## us assert the parsed AST directly. The companion `defaults_section_simple.nim`
## fixture then proves `parseDefaultsBlock` consumes that exact AST shape.

import std/macros

static:
  let parsed = parseStmt("defaults: CC: ccSingle")

  # Top level is a StmtList holding the single `defaults` call.
  doAssert parsed.kind == nnkStmtList
  doAssert parsed.len == 1

  let defaultsCall = parsed[0]
  doAssert defaultsCall.kind == nnkCall
  doAssert defaultsCall[0].eqIdent("defaults")

  # The crux: the `defaults` body is an `nnkStmtList`, NOT a bare
  # `nnkExprColonExpr`. This is exactly what `parseDefaultsBlock`'s body-finder
  # scans for, so the single-line form is handled identically to the multi-line.
  doAssert defaultsCall.len == 2
  let defaultsBody = defaultsCall[1]
  doAssert defaultsBody.kind == nnkStmtList
  doAssert defaultsBody.len == 1

  # The `CC: ccSingle` entry is itself an `nnkCall` with a StmtList body, consumed
  # by the entry loop's `nnkCall` branch.
  let entry = defaultsBody[0]
  doAssert entry.kind == nnkCall
  doAssert entry[0].eqIdent("CC")
  doAssert entry[1].kind == nnkStmtList
  doAssert entry[1][0].eqIdent("ccSingle")

echo "defaults_section_single_line passed"
