## Tests for the AST-based typestate parser.

import std/[os, unittest]
import nim_typestates/ast_parser

suite "AST Parser":
  test "parse basic typestate":
    let result = parseFileWithAst("tests/fixtures/basic_typestate.nim")
    check result.filesChecked == 1
    check result.typestates.len == 1

    let ts = result.typestates[0]
    check ts.name == "File"
    check ts.states == @["Closed", "Open"]
    check ts.transitions.len == 2
    check ts.isSealed == true
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
    check ts.isSealed == false
    check ts.strictTransitions == false

  test "file not found raises ParseError":
    expect ParseError:
      discard parseFileWithAst("tests/fixtures/nonexistent.nim")

  test "parse multiple files":
    let result = parseTypestatesAst(@["tests/fixtures/"])
    check result.filesChecked >= 5
    check result.typestates.len >= 5
