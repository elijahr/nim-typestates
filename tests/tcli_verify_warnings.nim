## CLI tests: verify() should populate warnings with reachability findings
## extracted from initial:/terminal: blocks.

import std/[unittest, sequtils, strutils]
import ../src/typestates/cli

suite "CLI verify warnings":
  test "dead state produces warning":
    let res = verify(@["tests/fixtures/cli_warning_dead.nim"])
    check res.warnings.anyIt("Dead state 'Frozen'" in it)
    check res.warnings.anyIt("Unreachable from any initial state" in it)

  test "AST parser extracts initial states":
    let pr = parseTypestates(@["tests/fixtures/cli_warning_dead.nim"])
    check pr.typestates.len == 1
    let ts = pr.typestates[0]
    check ts.name == "X"
    check ts.initialStates == @["A"]
    check ts.terminalStates.len == 0

  test "no warnings when initial/terminal not declared":
    # tests/fixtures/cli_warning_no_init.nim has no initial: block, so
    # the analyzer is skipped entirely. The gate is "no warnings AT ALL,"
    # not "no `Dead state` warning specifically" — a regression that
    # removed the gate would let any reachability finding through, not
    # only dead-state ones.
    let res = verify(@["tests/fixtures/cli_warning_no_init.nim"])
    check res.warnings.len == 0
