## Test: Module-qualified bridges appear correctly in DOT visualization
##
## This test verifies that:
## 1. Module qualifiers are preserved in unified DOT output
## 2. Bridge edges use fullDestRepr (includes module qualifier)
## 3. Separate DOT output shows bridges as terminal nodes with full qualifiers
## 4. Both with and without module qualifiers render correctly

import std/[os, strutils]
import ../src/typestates/cli
import ../src/typestates/ast_parser

# Test 1: Module-qualified bridge in unified view
block test_unified_with_module_qualifier:
  let sessionFile = "test_viz_session.nim"
  let authFile = "test_viz_auth.nim"

  let sessionContent =
    """
type
  Session = object
  Active = distinct Session

typestate Session:
  consumeOnTransition = false
  states Active
  transitions:
    Active -> Active
"""

  let authContent =
    """
type
  AuthFlow = object
  Authenticated = distinct AuthFlow

typestate AuthFlow:
  consumeOnTransition = false
  states Authenticated
  transitions:
    Authenticated -> Authenticated
  bridges:
    # Module-qualified bridge
    Authenticated -> sessionmodule.Session.Active
"""

  writeFile(sessionFile, sessionContent)
  writeFile(authFile, authContent)

  try:
    let parseResult = parseTypestates(@[sessionFile, authFile])
    let dot = generateUnifiedDot(parseResult.typestates)

    # Verify module qualifier appears in bridge edge (quoted for DOT compatibility)
    doAssert "\"sessionmodule.Session.Active\"" in dot,
      "Bridge should use full module-qualified name (quoted): " & dot
    doAssert "Authenticated -> \"sessionmodule.Session.Active\"" in dot,
      "Bridge edge should include module qualifier (quoted)"
    doAssert "style=dashed" in dot, "Bridge edge should be dashed"

    echo "Unified DOT with module qualifier test passed"
  finally:
    if fileExists(sessionFile):
      removeFile(sessionFile)
    if fileExists(authFile):
      removeFile(authFile)

# Test 2: Separate view with module-qualified bridge
block test_separate_with_module_qualifier:
  let authFile = "test_viz_separate.nim"

  let authContent =
    """
type
  AuthFlow = object
  Authenticated = distinct AuthFlow

typestate AuthFlow:
  consumeOnTransition = false
  states Authenticated
  transitions:
    Authenticated -> Authenticated
  bridges:
    Authenticated -> othermodule.Session.Active
"""

  writeFile(authFile, authContent)

  try:
    let parseResult = parseTypestates(@[authFile])
    doAssert parseResult.typestates.len == 1, "Should parse one typestate"

    let ts = parseResult.typestates[0]
    let dot = generateSeparateDot(ts)

    # In separate mode, bridges are shown as terminal nodes
    # Should use quoted node name with full qualifier
    doAssert "\"othermodule.Session.Active\"" in dot,
      "Bridge destination should be quoted with module qualifier: " & dot
    doAssert "Authenticated -> \"othermodule.Session.Active\"" in dot,
      "Bridge edge should reference fully qualified node"
    doAssert "style=dashed" in dot, "Bridge edge should be dashed"

    echo "Separate DOT with module qualifier test passed"
  finally:
    if fileExists(authFile):
      removeFile(authFile)

# Test 3: Multiple bridges with different module qualifiers
block test_multiple_module_qualifiers:
  let multiFile = "test_viz_multi.nim"

  let multiContent =
    """
type
  Workflow = object
  Processing = distinct Workflow

typestate Workflow:
  consumeOnTransition = false
  states Processing
  bridges:
    Processing -> moduleA.TypeX.StateX
    Processing -> moduleB.TypeY.StateY
    Processing -> moduleC.deep.nested.TypeZ.StateZ
"""

  writeFile(multiFile, multiContent)

  try:
    let parseResult = parseTypestates(@[multiFile])
    let ts = parseResult.typestates[0]
    let dot = generateSeparateDot(ts)

    # All module qualifiers should be preserved
    doAssert "\"moduleA.TypeX.StateX\"" in dot, "Should preserve moduleA qualifier"
    doAssert "\"moduleB.TypeY.StateY\"" in dot, "Should preserve moduleB qualifier"
    doAssert "\"moduleC.deep.nested.TypeZ.StateZ\"" in dot,
      "Should preserve deep nested module qualifier"

    echo "Multiple module qualifiers test passed"
  finally:
    if fileExists(multiFile):
      removeFile(multiFile)

# Test 4: Compare with and without module qualifier
block test_with_without_comparison:
  let compareFile = "test_viz_compare.nim"

  let compareContent =
    """
type
  Source = object
  StateA = distinct Source
  StateB = distinct Source

typestate Source:
  consumeOnTransition = false
  states StateA, StateB
  bridges:
    StateA -> Dest.TargetX
    StateB -> mymodule.Dest.TargetY
"""

  writeFile(compareFile, compareContent)

  try:
    let parseResult = parseTypestates(@[compareFile])
    let ts = parseResult.typestates[0]
    let dot = generateSeparateDot(ts)

    # Without module qualifier: just Typestate.State
    doAssert "\"Dest.TargetX\"" in dot,
      "Bridge without module should be Typestate.State"

    # With module qualifier: module.Typestate.State
    doAssert "\"mymodule.Dest.TargetY\"" in dot,
      "Bridge with module should be module.Typestate.State"

    # Both should have bridge edges
    doAssert "StateA -> \"Dest.TargetX\"" in dot
    doAssert "StateB -> \"mymodule.Dest.TargetY\"" in dot

    echo "Comparison with/without module qualifier test passed"
  finally:
    if fileExists(compareFile):
      removeFile(compareFile)

# Test 5: Wildcard bridge with module qualifier
block test_wildcard_with_module:
  let wildcardFile = "test_viz_wildcard.nim"

  let wildcardContent =
    """
type
  Task = object
  Ready = distinct Task
  Running = distinct Task
  Done = distinct Task

typestate Task:
  consumeOnTransition = false
  states Ready, Running, Done
  transitions:
    Ready -> Running
    Running -> Done
  bridges:
    * -> emergency.Shutdown.Terminated
"""

  writeFile(wildcardFile, wildcardContent)

  try:
    let parseResult = parseTypestates(@[wildcardFile])
    let ts = parseResult.typestates[0]
    let dot = generateSeparateDot(ts)

    # Wildcard should expand to all states
    doAssert "Ready -> \"emergency.Shutdown.Terminated\"" in dot,
      "Wildcard should create bridge from Ready"
    doAssert "Running -> \"emergency.Shutdown.Terminated\"" in dot,
      "Wildcard should create bridge from Running"
    doAssert "Done -> \"emergency.Shutdown.Terminated\"" in dot,
      "Wildcard should create bridge from Done"

    echo "Wildcard bridge with module qualifier test passed"
  finally:
    if fileExists(wildcardFile):
      removeFile(wildcardFile)

echo "All visualization tests for module-qualified bridges passed"
