## Test: Multi-module sealed typestates sharing state names (MED-01)
## Verifies that multiple modules defining sealed typestates with identical
## state names (e.g. Closed, Open) do not collide or falsely report local
## states as external.

import std/[options, os, osproc, strutils]
import ../src/typestates/pragmas

# 1. Compile-time unit test of registerSealedStates and isStateFromSealedTypestate
static:
  registerSealedStates("/path/to/door.nim", @["Closed", "Open"])
  registerSealedStates("/path/to/circuit.nim", @["Closed", "Open", "Tripped"])

  # Querying from door.nim: both Closed and Open must be recognized as local (isNone)
  doAssert isStateFromSealedTypestate("Closed", "/path/to/door.nim").isNone,
    "Closed should be local to door.nim"
  doAssert isStateFromSealedTypestate("Open", "/path/to/door.nim").isNone,
    "Open should be local to door.nim"
  # Tripped only belongs to circuit.nim, so from door.nim it must be external
  doAssert isStateFromSealedTypestate("Tripped", "/path/to/door.nim").isSome,
    "Tripped should be external to door.nim"
  doAssert isStateFromSealedTypestate("Tripped", "/path/to/door.nim").get ==
    "/path/to/circuit.nim"

  # Querying from circuit.nim: Closed, Open, Tripped must all be recognized as local (isNone)
  doAssert isStateFromSealedTypestate("Closed", "/path/to/circuit.nim").isNone,
    "Closed should be local to circuit.nim"
  doAssert isStateFromSealedTypestate("Open", "/path/to/circuit.nim").isNone,
    "Open should be local to circuit.nim"
  doAssert isStateFromSealedTypestate("Tripped", "/path/to/circuit.nim").isNone,
    "Tripped should be local to circuit.nim"

  # Querying from an unrelated 3rd module:
  doAssert isStateFromSealedTypestate("Closed", "/path/to/app.nim").isSome,
    "Closed should be external to app.nim"
  let closedOwner = isStateFromSealedTypestate("Closed", "/path/to/app.nim").get
  doAssert closedOwner == "/path/to/door.nim" or closedOwner == "/path/to/circuit.nim"

  doAssert isStateFromSealedTypestate("Tripped", "/path/to/app.nim").isSome,
    "Tripped should be external to app.nim"
  doAssert isStateFromSealedTypestate("Tripped", "/path/to/app.nim").get ==
    "/path/to/circuit.nim"

  doAssert isStateFromSealedTypestate("NonExistent", "/path/to/app.nim").isNone,
    "NonExistent state should return none"

proc main() =
  defer:
    removeFile("tests/fixtures/sealed_multimodule/consumer")
    removeFile("tests/fixtures/sealed_multimodule/consumer.exe")
    removeFile("tests/fixtures/sealed_multimodule/external_fail")
    removeFile("tests/fixtures/sealed_multimodule/external_fail.exe")

  # 2. Integration test: compile and execute consumer importing both modules
  let (outVal, code) =
    execCmdEx("nim c -r tests/fixtures/sealed_multimodule/consumer.nim")
  if code != 0:
    echo "FAIL: consumer.nim failed to compile/run"
    echo outVal
    quit(1)

  # 3. Negative integration test: external module attempting transition on sealed typestate must fail
  let (failOut, failCode) =
    execCmdEx("nim c tests/fixtures/sealed_multimodule/external_fail.nim")
  if failCode == 0:
    echo "FAIL: external_fail.nim was expected to fail compilation but succeeded"
    quit(1)
  doAssert "Cannot define transition on typestate 'Door' from external module" in failOut,
    "Expected external sealed module diagnostic, got:\n" & failOut

  echo "PASS: multi-module sealed state collision test (MED-01)"

main()
