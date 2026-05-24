## Discriminative fixtures for the AST-based `verify` proc classifier (RED).
##
## Each test below asserts the CORRECT, post-AST-rewrite behavior for a fixture
## under `tests/fixtures/ast_verify/`. The current text-based scanner
## (`verifyFile` in `src/typestates/cli.nim`) classifies procs line-by-line via
## substring matching, which gets several of these wrong. The assertions here
## therefore encode the CONTRACT the AST rewrite must satisfy — many of them
## are EXPECTED TO FAIL right now (that is the RED phase).
##
## Each test is annotated with `RED under old scanner` (currently fails) or
## `GREEN control` (currently passes; guards against regression). The mapping
## was captured against the v0.9.3 binary built from `src/typestates_bin.nim`:
##
##   RED (fail now): multiline_unmarked, combined_pragma_not,
##                   combined_pragma_transition, generic_concrete_param,
##                   comment_literal, unmarked_var_param, unmarked_sink_param,
##                   overloaded, ref_ptr_param
##   GREEN control:  multiline_marked, non_strict_warning, non_exported,
##                   no_typestate_param
##
## API mirrors tests/tcli_verify_warnings.nim: call `verify(@[path])` and
## inspect `result.findings` / `errors` / `warnings`.

import std/[unittest, sequtils, strutils, os]
import ../src/typestates/cli
import ../src/typestates/findings

const FixDir = "tests/fixtures/ast_verify"

proc fixture(name: string): string =
  FixDir / name

proc errorsFor(path: string): seq[Finding] =
  verify(@[path]).errors

proc warningsFor(path: string): seq[Finding] =
  verify(@[path]).warnings

suite "AST verify: GROUP A (correct under AST, wrong under old scanner)":
  test "multiline_marked: marked transition with multi-line header -> NO finding":
    # GREEN control. A valid multi-line transition must not be flagged.
    let errs = errorsFor(fixture("multiline_marked.nim"))
    check errs.len == 0

  test "multiline_unmarked: unmarked multi-line proc on strict -> ONE error":
    # RED under old scanner (LINCHPIN green-mirage guard). The text scanner
    # never sees the param `m: Idle` because it lives on a line after the
    # `proc mutate(` line, so it emits nothing. The AST verifier must flag it.
    let errs = errorsFor(fixture("multiline_unmarked.nim"))
    check errs.len == 1
    check errs[0].code == fcUnmarkedProcStrict
    # The finding must anchor to the proc definition line (`proc mutate(`).
    check errs[0].line == 26

  test "combined_pragma_not: combined block with notATransition -> NO finding":
    # RED under old scanner. `{.discardable, raises: [], notATransition.}` is a
    # valid marker; the scanner false-flags it because the exact substring
    # `{.notATransition.}` is absent.
    let errs = errorsFor(fixture("combined_pragma_not.nim"))
    check errs.len == 0

  test "combined_pragma_transition: combined block with transition -> NO finding":
    # RED under old scanner. `{.raises: [], transition.}` is a valid transition;
    # the scanner false-flags it because `{.transition.}` is absent verbatim.
    let res = verify(@[fixture("combined_pragma_transition.nim")])
    check res.errors.len == 0
    # And it must count as a checked transition.
    check res.transitionsChecked == 1

  test "generic_concrete_param: generic state param, combined notATransition -> NO finding":
    # RED under old scanner. Param `s: Stage1[T]` is a generic state; the proc
    # is marked notATransition inside a combined block the scanner cannot read.
    let errs = errorsFor(fixture("generic_concrete_param.nim"))
    check errs.len == 0

suite "AST verify: GROUP B (must stay flagged / must not over-match)":
  test "comment_literal: marker text in comment+string is NOT a pragma -> ONE error":
    # RED under old scanner. The literal `{.notATransition.}` appears in a
    # trailing comment and a string literal on the proc line; the raw substring
    # test fools the scanner into treating the proc as marked.
    let errs = errorsFor(fixture("comment_literal.nim"))
    check errs.len == 1
    check errs[0].code == fcUnmarkedProcStrict

  test "unmarked_var_param: var <State> unmarked on strict -> ONE error":
    # RED under old scanner. Extracted param type `var Open` is not in `states`.
    let errs = errorsFor(fixture("unmarked_var_param.nim"))
    check errs.len == 1
    check errs[0].code == fcUnmarkedProcStrict

  test "unmarked_sink_param: sink <State> unmarked on strict -> ONE error":
    # RED under old scanner. Extracted param type `sink Open` is not in `states`.
    let errs = errorsFor(fixture("unmarked_sink_param.nim"))
    check errs.len == 1
    check errs[0].code == fcUnmarkedProcStrict

  test "non_strict_warning: unmarked on non-strict typestate -> ONE warning":
    # GREEN control (severity routing). strictTransitions = false downgrades the
    # unmarked proc to a warning, not an error.
    let res = verify(@[fixture("non_strict_warning.nim")])
    check res.errors.len == 0
    check res.warnings.len == 1
    check res.warnings[0].code == fcUnmarkedProc

suite "AST verify: GROUP C (robustness)":
  test "overloaded: one marked + one unmarked overload -> EXACTLY ONE error":
    # RED under old scanner. The marked overload uses a combined pragma the
    # scanner cannot read, so it false-flags BOTH overloads (2 errors). The AST
    # verifier must flag only the genuinely unmarked overload.
    let errs = errorsFor(fixture("overloaded.nim"))
    check errs.len == 1
    check errs[0].code == fcUnmarkedProcStrict
    # Must anchor to the unmarked overload (`proc step(c: A, extra: int)`),
    # NOT the marked one.
    check errs[0].line == 28

  test "non_exported: unmarked private proc on strict -> ONE error":
    # GREEN control. Visibility does not exempt a proc from marking.
    let errs = errorsFor(fixture("non_exported.nim"))
    check errs.len == 1
    check errs[0].code == fcUnmarkedProcStrict

  test "ref_ptr_param: ref/ptr <State> unmarked on strict -> TWO errors":
    # RED under old scanner. Extracted param types `ref Open` / `ptr Open` are
    # not in `states`, so both procs slip through. The AST verifier must peel
    # the pointer indirection and flag both.
    let errs = errorsFor(fixture("ref_ptr_param.nim"))
    check errs.len == 2
    check errs.allIt(it.code == fcUnmarkedProcStrict)

  test "no_typestate_param: procs with no typestate param -> NO finding":
    # GREEN control (over-match guard). Unrelated procs must not be flagged.
    let res = verify(@[fixture("no_typestate_param.nim")])
    check res.errors.len == 0
    check res.warnings.len == 0

suite "AST verify: GROUP D (peel-discriminator integration)":
  ## verify()-level assertions for the two peel-discriminator fixtures whose
  ## helper-level behavior is unit-tested in tests/tast_classify.nim. These
  ## close the integration loop deferred in that file's TODOs: they confirm the
  ## peel semantics survive end-to-end through verify().
  test "distinct_guard: non-state distinct alias param -> ZERO findings":
    # A `distinct int` alias used as a param must NOT over-peel to a state, so
    # the only state proc (marked `{.transition.}`) is fine and the whole file
    # is clean. A regression that peeled distinct through to its base would
    # falsely flag `useToken`.
    let res = verify(@[fixture("distinct_guard.nim")])
    check res.errors.len == 0
    check res.warnings.len == 0

  test "multipeel_var_ptr: var ptr <State> unmarked on strict -> ONE error":
    # The peel must traverse BOTH `var` and `ptr` wrappers to reach the state
    # base, so the unmarked proc on a strict typestate is flagged.
    let errs = errorsFor(fixture("multipeel_var_ptr.nim"))
    check errs.len == 1
    check errs[0].code == fcUnmarkedProcStrict
