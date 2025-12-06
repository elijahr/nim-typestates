## Tests for CLI parsing and DOT generation

import std/[strutils, os]
import ../src/typestates/cli

# Test parseTypestates with a fixture file
block testParseTypestates:
  # Create a temp file with typestate definition
  let tempDir = getTempDir()
  let testFile = tempDir / "test_typestate.nim"

  writeFile(testFile, """
type
  File = object
  Closed = distinct File
  Open = distinct File
  Errored = distinct File

typestate File:
  consumeOnTransition = false  # Opt out for existing tests
  states Closed, Open, Errored
  transitions:
    Closed -> Open | Errored as OpenResult
    Open -> Closed
    * -> Closed
""")

  let result = parseTypestates(@[testFile])

  doAssert result.filesChecked == 1, "Expected 1 file checked"
  doAssert result.typestates.len == 1, "Expected 1 typestate"

  let ts = result.typestates[0]
  doAssert ts.name == "File", "Expected typestate name 'File', got: " & ts.name
  doAssert ts.states.len == 3, "Expected 3 states, got: " & $ts.states.len
  doAssert "Closed" in ts.states
  doAssert "Open" in ts.states
  doAssert "Errored" in ts.states
  doAssert ts.transitions.len == 3, "Expected 3 transitions, got: " & $ts.transitions.len

  # Check branching transition
  var foundBranching = false
  for trans in ts.transitions:
    if trans.fromState == "Closed":
      doAssert trans.toStates.len == 2
      doAssert "Open" in trans.toStates
      doAssert "Errored" in trans.toStates
      foundBranching = true
  doAssert foundBranching, "Expected branching transition from Closed"

  # Check wildcard
  var foundWildcard = false
  for trans in ts.transitions:
    if trans.isWildcard:
      doAssert trans.fromState == "*"
      doAssert "Closed" in trans.toStates
      foundWildcard = true
  doAssert foundWildcard, "Expected wildcard transition"

  removeFile(testFile)
  echo "parseTypestates test passed"

# Test generateDot
block testGenerateDot:
  let ts = ParsedTypestate(
    name: "Connection",
    states: @["Disconnected", "Connected", "Errored"],
    transitions: @[
      ParsedTransition(fromState: "Disconnected", toStates: @["Connected", "Errored"]),
      ParsedTransition(fromState: "Connected", toStates: @["Disconnected"]),
      ParsedTransition(fromState: "*", toStates: @["Disconnected"], isWildcard: true)
    ]
  )

  let dot = generateDot(ts)

  doAssert "digraph Connection" in dot, "Expected digraph header"
  doAssert "rankdir=TB" in dot, "Expected TB direction"
  doAssert "Disconnected;" in dot, "Expected Disconnected node"
  doAssert "Connected;" in dot, "Expected Connected node"
  doAssert "Errored;" in dot, "Expected Errored node"
  doAssert "Disconnected -> Connected" in dot, "Expected Disconnected -> Connected edge"
  doAssert "Disconnected -> Errored" in dot, "Expected Disconnected -> Errored edge"
  doAssert "Connected -> Disconnected" in dot, "Expected Connected -> Disconnected edge"
  # Wildcard should expand
  doAssert "Errored -> Disconnected" in dot, "Expected Errored -> Disconnected (from wildcard)"
  doAssert "style=dotted" in dot, "Expected dotted style for wildcard edges"

  echo "generateDot test passed"

# Test verify
block testVerify:
  let tempDir = getTempDir()
  let testFile = tempDir / "test_verify.nim"

  writeFile(testFile, """
type
  File = object
  Closed = distinct File
  Open = distinct File

typestate File:
  consumeOnTransition = false  # Opt out for existing tests
  states Closed, Open
  transitions:
    Closed -> Open

proc open(f: Closed): Open {.transition.} =
  result = Open(f)

proc read(f: Open): string {.notATransition.} =
  result = "data"
""")

  let result = verify(@[testFile])

  doAssert result.errors.len == 0, "Expected no errors, got: " & $result.errors
  doAssert result.transitionsChecked >= 2, "Expected at least 2 transitions checked"

  removeFile(testFile)
  echo "verify test passed"

# Test verify catches unmarked procs
block testVerifyUnmarked:
  let tempDir = getTempDir()
  let testFile = tempDir / "test_verify_unmarked.nim"

  writeFile(testFile, """
type
  File = object
  Closed = distinct File
  Open = distinct File

typestate File:
  consumeOnTransition = false  # Opt out for existing tests
  states Closed, Open
  transitions:
    Closed -> Open

proc unmarkedProc(f: Closed): string =
  result = "bad"
""")

  let result = verify(@[testFile])

  doAssert result.errors.len > 0, "Expected errors for unmarked proc"
  doAssert "unmarkedProc" in result.errors[0] or "Unmarked" in result.errors[0],
    "Expected error about unmarked proc"

  removeFile(testFile)
  echo "verify unmarked test passed"

echo "All CLI tests passed"
