import std/[os, strutils]
import ../src/typestates/cli
import ../src/typestates/ast_parser

# Create test files
let sessionFile = "test_session.nim"
let authFile = "test_auth.nim"

let sessionContent = """
type
  Session = object
  Active = distinct Session
  Closed = distinct Session

typestate Session:
  consumeOnTransition = false  # Opt out for existing tests
  states Active, Closed
  transitions:
    Active -> Closed
"""

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

writeFile(sessionFile, sessionContent)
writeFile(authFile, authContent)

try:
  let parseResult = parseTypestates(@[sessionFile, authFile])
  let dot = generateUnifiedDot(parseResult.typestates)

  # Verify structure
  doAssert "digraph" in dot, "Should be a digraph"
  doAssert "subgraph cluster_AuthFlow" in dot, "Should have AuthFlow subgraph"
  doAssert "subgraph cluster_Session" in dot, "Should have Session subgraph"

  # Verify bridge edges (dashed, cross-cluster)
  # Bridges should use fullDestRepr with quotes for DOT compatibility (e.g., "Session.Active")
  doAssert "Authenticated -> \"Session.Active\"" in dot, "Should have bridge from Authenticated to Session.Active"
  doAssert "Failed -> \"Session.Closed\"" in dot, "Should have bridge from Failed to Session.Closed"
  doAssert "style=dashed" in dot, "Bridge edges should be dashed"

  echo "Unified graph generation test passed"
finally:
  if fileExists(sessionFile): removeFile(sessionFile)
  if fileExists(authFile): removeFile(authFile)
