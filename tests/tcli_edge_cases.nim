## Tests for CLI edge cases.

import std/[osproc, strutils]

# Test that syntax errors cause verification to fail with clear message
block syntaxErrorTest:
  let (output, exitCode) = execCmdEx("nim c -r --hints:off --path:src src/typestates_bin.nim verify tests/fixtures/syntax_error.nim 2>&1")

  if exitCode != 1:
    echo "FAIL: Expected exit code 1 for syntax error, got ", exitCode
    quit(1)

  # Check for error message mentioning the file
  if "error" notin output.toLower or "syntax_error.nim" notin output.toLower:
    echo "FAIL: Expected clear error message about syntax error"
    echo "Output:"
    echo output
    quit(1)

  echo "PASS: Syntax errors cause verification to fail with clear message"

# Test parsing multiple files works correctly
block multiFileTest:
  let (output, exitCode) = execCmdEx("nim c -r --hints:off --path:src src/typestates_bin.nim dot tests/fixtures/basic_typestate.nim tests/fixtures/with_flags.nim 2>&1")

  if exitCode != 0:
    echo "FAIL: Expected exit code 0, got ", exitCode
    echo "Output:"
    echo output
    quit(1)

  # Check that both typestates are in unified output (subgraph clusters)
  if "subgraph cluster_File" notin output or "subgraph cluster_Task" notin output:
    echo "FAIL: Expected both typestates in unified DOT output"
    echo "Output:"
    echo output
    quit(1)

  echo "PASS: Multi-file parsing works correctly"

# Test that dot command produces valid DOT output
block dotOutputTest:
  let (output, exitCode) = execCmdEx("nim c -r --hints:off --path:src src/typestates_bin.nim dot tests/fixtures/branching_transitions.nim 2>&1")

  if exitCode != 0:
    echo "FAIL: dot command failed"
    echo "Output:"
    echo output
    quit(1)

  # Check for DOT syntax elements (unified graph with subgraph cluster)
  if "digraph {" notin output or "subgraph cluster_Request" notin output:
    echo "FAIL: Expected unified digraph with Request subgraph in DOT output"
    quit(1)

  if "Pending -> Success" notin output:
    echo "FAIL: Expected transitions in DOT output"
    quit(1)

  echo "PASS: DOT output is valid"

echo "All CLI edge case tests passed!"
