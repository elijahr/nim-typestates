import std/[os, strutils]
import ../src/typestates/ast_parser

# Create temporary test file
let testFile = "test_bridges_ast.nim"
let content = """
type
  Session = object
  Active = distinct Session

typestate Session:
  consumeOnTransition = false  # Opt out for existing tests
  states Active
  transitions:
    Active -> Active

type
  AuthFlow = object
  Authenticated = distinct AuthFlow
  Failed = distinct AuthFlow

typestate AuthFlow:
  consumeOnTransition = false  # Opt out for existing tests
  states Authenticated, Failed
  transitions:
    Authenticated -> Failed
  bridges:
    Authenticated -> Session.Active
    Failed -> Session.Active
"""

writeFile(testFile, content)

try:
  let result = parseFileWithAst(testFile)

  # Find AuthFlow typestate
  var authFlow: ParsedTypestate
  for ts in result.typestates:
    if ts.name == "AuthFlow":
      authFlow = ts
      break

  doAssert authFlow.name == "AuthFlow", "Should find AuthFlow typestate"
  doAssert authFlow.bridges.len == 2, "Should parse 2 bridges, got: " & $authFlow.bridges.len
  doAssert authFlow.bridges[0].fromState == "Authenticated", "First bridge source should be Authenticated"
  doAssert authFlow.bridges[0].toTypestate == "Session", "First bridge typestate should be Session"
  doAssert authFlow.bridges[0].toState == "Active", "First bridge state should be Active"
  doAssert authFlow.bridges[1].fromState == "Failed", "Second bridge source should be Failed"

  echo "AST bridge parser test passed"
finally:
  if fileExists(testFile):
    removeFile(testFile)
