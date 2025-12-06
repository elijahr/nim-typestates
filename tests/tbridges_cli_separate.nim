import std/[os, strutils]
import ../src/typestates/cli
import ../src/typestates/ast_parser

# Create test file
let authFile = "test_auth_separate.nim"

let authContent = """
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
    Failed -> Session.Closed
"""

writeFile(authFile, authContent)

try:
  let parseResult = parseTypestates(@[authFile])

  # Get the AuthFlow typestate
  var authFlow: ParsedTypestate
  for ts in parseResult.typestates:
    if ts.name == "AuthFlow":
      authFlow = ts
      break

  let dot = generateSeparateDot(authFlow)

  # Verify structure
  doAssert "digraph AuthFlow" in dot, "Should be named digraph AuthFlow"
  doAssert "subgraph" notin dot, "Should not have subgraphs"

  # Verify states
  doAssert "Authenticated" in dot, "Should have Authenticated state"
  doAssert "Failed" in dot, "Should have Failed state"

  # Verify transitions
  doAssert "Authenticated -> Failed" in dot, "Should have regular transition"

  # Verify bridges shown as terminal nodes
  doAssert "\"Session.Active\"" in dot, "Should have Session.Active as terminal node"
  doAssert "\"Session.Closed\"" in dot, "Should have Session.Closed as terminal node"
  doAssert "Authenticated -> \"Session.Active\"" in dot, "Should have bridge to terminal"
  doAssert "Failed -> \"Session.Closed\"" in dot, "Should have bridge to terminal"
  doAssert "style=dashed" in dot, "Bridge edges should be dashed"

  echo "Separate graph generation test passed"
finally:
  if fileExists(authFile): removeFile(authFile)
