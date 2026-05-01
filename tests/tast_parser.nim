## Tests for the AST-based typestate parser.

import std/unittest
import ../src/typestates/ast_parser

suite "AST Parser":
  test "parse basic typestate":
    let result = parseFileWithAst("tests/fixtures/basic_typestate.nim")
    check result.filesChecked == 1
    check result.typestates.len == 1

    let ts = result.typestates[0]
    check ts.name == "File"
    check ts.states == @["Closed", "Open"]
    check ts.transitions.len == 2
    check ts.strictTransitions == true

  test "parse typestate with comments":
    let result = parseFileWithAst("tests/fixtures/typestate_with_comments.nim")
    check result.filesChecked == 1
    check result.typestates.len == 1

    let ts = result.typestates[0]
    check ts.name == "Connection"
    check ts.states.len == 2
    check "Disconnected" in ts.states
    check "Connected" in ts.states

  test "parse branching transitions":
    let result = parseFileWithAst("tests/fixtures/branching_transitions.nim")
    check result.typestates.len == 1

    let ts = result.typestates[0]
    check ts.name == "Request"
    check ts.states.len == 4

    # Find the branching transition
    var foundBranching = false
    for trans in ts.transitions:
      if trans.fromState == "Pending":
        check trans.toStates.len == 3
        check "Success" in trans.toStates
        check "Failed" in trans.toStates
        check "Cancelled" in trans.toStates
        foundBranching = true
    check foundBranching

  test "parse wildcard transitions":
    let result = parseFileWithAst("tests/fixtures/wildcard_transitions.nim")
    check result.typestates.len == 1

    let ts = result.typestates[0]
    check ts.name == "Resource"

    # Find the wildcard transition
    var foundWildcard = false
    for trans in ts.transitions:
      if trans.isWildcard:
        check trans.fromState == "*"
        check "Stopped" in trans.toStates
        foundWildcard = true
    check foundWildcard

  test "parse flags":
    let result = parseFileWithAst("tests/fixtures/with_flags.nim")
    check result.typestates.len == 1

    let ts = result.typestates[0]
    check ts.name == "Task"
    check ts.strictTransitions == false

  test "parse opaqueStates flag":
    let res = parseFileWithAst("tests/fixtures/opaque_states_basic.nim")
    check res.typestates.len == 1
    check res.typestates[0].opaqueStates == true

  test "opaqueStates defaults to false":
    let res = parseFileWithAst("tests/fixtures/basic_typestate.nim")
    check res.typestates.len == 1
    check res.typestates[0].opaqueStates == false

  test "opaqueStates explicit false":
    let res = parseFileWithAst("tests/fixtures/with_flags.nim")
    check res.typestates.len == 1
    check res.typestates[0].opaqueStates == false

  test "file not found raises ParseError":
    expect ParseError:
      discard parseFileWithAst("tests/fixtures/nonexistent.nim")

  # Note: syntax errors in Nim files cause the compiler to emit errors directly
  # rather than raising exceptions, so we can't easily test this case in a unit test.
  # The CLI tool handles this by letting the error propagate to the user.

  test "parse initial: and terminal: blocks":
    # cli_warning_dead.nim declares `initial: A` (no terminal:); cli_warning_no_init.nim
    # declares neither. Both fixtures exercise the new extractors.
    let dead = parseFileWithAst("tests/fixtures/cli_warning_dead.nim")
    check dead.typestates.len == 1
    check dead.typestates[0].name == "X"
    check dead.typestates[0].initialStates == @["A"]
    check dead.typestates[0].terminalStates.len == 0

    let noInit = parseFileWithAst("tests/fixtures/cli_warning_no_init.nim")
    check noInit.typestates.len == 1
    check noInit.typestates[0].name == "Y"
    check noInit.typestates[0].initialStates.len == 0
    check noInit.typestates[0].terminalStates.len == 0

  test "parse multiline initial and terminal blocks":
    let res = parseFileWithAst("tests/fixtures/initial_terminal_multi.nim")
    check res.typestates.len == 1
    let ts = res.typestates[0]
    check ts.name == "M"
    # `initial:` block contains A, B; `terminal:` contains D, E
    check ts.initialStates == @["A", "B"]
    check ts.terminalStates == @["D", "E"]

  test "parse multiple files":
    # Parse specific valid files to avoid syntax_error.nim
    let result = parseTypestatesAst(
      @[
        "tests/fixtures/basic_typestate.nim",
        "tests/fixtures/branching_transitions.nim",
        "tests/fixtures/typestate_with_comments.nim",
        "tests/fixtures/wildcard_transitions.nim", "tests/fixtures/with_flags.nim",
      ]
    )
    check result.filesChecked == 5
    check result.typestates.len == 5
