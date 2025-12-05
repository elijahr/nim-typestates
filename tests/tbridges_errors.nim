# This file documents expected error messages for bridge validation
# Each test case should fail compilation with the documented error
#
# To test error messages:
# 1. Uncomment one test case at a time
# 2. Run: nim c tests/tbridges_errors.nim
# 3. Verify the error message matches the expected output
# 4. Re-comment the test case
# 5. Repeat for each test case

# ==============================================================================
# Test 1: Undeclared bridge
# ==============================================================================
# Uncomment to test:

# import ../src/typestates
#
# type
#   Session = object
#   Active = distinct Session
#
# typestate Session:
#   states Active
#   transitions:
#     Active -> Active
#
# type
#   AuthFlow = object
#   Authenticated = distinct AuthFlow
#
# typestate AuthFlow:
#   states Authenticated
#   transitions:
#     Authenticated -> Authenticated
#   # Note: No bridges declared
#
# proc startSession(auth: Authenticated): Active {.transition.} =
#   result = Active(Session())

# Expected error:
# Error: Undeclared bridge: Authenticated -> Session.Active
#   Typestate 'AuthFlow' does not declare this bridge.
#   Valid bridges from 'Authenticated': @[]
#   Hint: Add 'bridges: Authenticated -> Session.Active' to AuthFlow.

# ==============================================================================
# Test 2: Bridge declared but destination typestate doesn't exist
# ==============================================================================
# This test requires that UnknownTypestate is truly not defined.
# The bridge parser will accept the declaration, but the transition pragma
# will fail to find the destination typestate.
#
# Note: This error currently manifests as "not part of any registered typestate"
# on the destination type since we look up the state in any typestate.

# ==============================================================================
# Test 3: Bridge declared but destination state doesn't exist in typestate
# ==============================================================================
# Similar to Test 2, if the destination state doesn't exist in the destination
# typestate, the lookup will fail.

echo "Error message test cases documented"
echo "Uncomment each test case individually to verify error messages"
