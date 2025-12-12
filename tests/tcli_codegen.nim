## Tests for CLI codegen command
##
## These tests verify the generated code is:
## 1. Syntactically correct (can be parsed)
## 2. Contains expected constructs
## 3. Would compile if used

import std/[strutils, os, osproc]
import ../src/typestates/cli

# Test generateCode produces valid Nim for simple typestate
block testGenerateCodeSimple:
  let ts = ParsedTypestate(
    name: "File",
    states: @["Closed", "Open", "Errored"],
    transitions: @[
      ParsedTransition(fromState: "Closed", toStates: @["Open"]),
      ParsedTransition(fromState: "Open", toStates: @["Closed"])
    ]
  )

  let code = generateCode(ts)

  # Verify enum is generated correctly
  doAssert "FileState* = enum" in code, "Missing state enum"
  doAssert "fsClosed" in code, "Missing fsClosed enum value"
  doAssert "fsOpen" in code, "Missing fsOpen enum value"
  doAssert "fsErrored" in code, "Missing fsErrored enum value"

  # Verify union type
  doAssert "FileStates* = Closed | Open | Errored" in code, "Missing union type"

  # Verify state procs
  doAssert "proc state*(f: Closed): FileState = fsClosed" in code, "Missing state proc for Closed"
  doAssert "proc state*(f: Open): FileState = fsOpen" in code, "Missing state proc for Open"
  doAssert "proc state*(f: Errored): FileState = fsErrored" in code, "Missing state proc for Errored"

  echo "generateCode simple test passed"

# Test generateCode with branching transitions
block testGenerateCodeBranching:
  let ts = ParsedTypestate(
    name: "Connection",
    states: @["Disconnected", "Connected", "Failed"],
    transitions: @[
      ParsedTransition(fromState: "Disconnected", toStates: @["Connected", "Failed"]),
      ParsedTransition(fromState: "Connected", toStates: @["Disconnected"])
    ]
  )

  let code = generateCode(ts)

  # Verify branch enum is generated
  doAssert "DisconnectedResultKind* = enum" in code, "Missing branch kind enum"
  doAssert "dConnected" in code, "Missing dConnected enum value"
  doAssert "dFailed" in code, "Missing dFailed enum value"

  # Verify branch object variant
  doAssert "DisconnectedResult* = object" in code, "Missing branch object"
  doAssert "case kind*: DisconnectedResultKind" in code, "Missing kind field"
  doAssert "of dConnected:" in code, "Missing dConnected branch"
  doAssert "connected*: Connected" in code, "Missing connected field"
  doAssert "of dFailed:" in code, "Missing dFailed branch"
  doAssert "failed*: Failed" in code, "Missing failed field"

  # Verify constructors
  doAssert "proc toDisconnectedResult*(s: sink Connected): DisconnectedResult" in code,
    "Missing constructor for Connected"
  doAssert "proc toDisconnectedResult*(s: sink Failed): DisconnectedResult" in code,
    "Missing constructor for Failed"

  # Verify -> operator
  doAssert "template `->`*(_: typedesc[DisconnectedResult], s: sink Connected)" in code,
    "Missing -> operator for Connected"

  echo "generateCode branching test passed"

# Test generateCode with generic types
block testGenerateCodeGeneric:
  let ts = ParsedTypestate(
    name: "Container",
    states: @["Empty[T]", "Full[T]"],
    transitions: @[
      ParsedTransition(fromState: "Empty[T]", toStates: @["Full[T]"])
    ]
  )

  let code = generateCode(ts)

  # Verify enum uses base names (without [T])
  doAssert "ContainerState* = enum" in code, "Missing state enum"
  doAssert "fsEmpty" in code, "Missing fsEmpty (base name)"
  doAssert "fsFull" in code, "Missing fsFull (base name)"
  doAssert "fsEmpty[T]" notin code, "Should use base name, not generic"

  # Verify union preserves generic params
  doAssert "ContainerStates* = Empty[T] | Full[T]" in code, "Missing generic union type"

  # Verify state procs use full generic type
  doAssert "proc state*(f: Empty[T]): ContainerState = fsEmpty" in code,
    "Missing state proc for Empty[T]"

  echo "generateCode generic test passed"

# CONSUMPTION TEST: Verify generated code can be compiled
block testGenerateCodeCompiles:
  let tempDir = getTempDir()
  let testFile = tempDir / "test_codegen_output.nim"

  # Create a complete, compilable file with types + generated code
  let ts = ParsedTypestate(
    name: "Light",
    states: @["Off", "On"],
    transitions: @[
      ParsedTransition(fromState: "Off", toStates: @["On"]),
      ParsedTransition(fromState: "On", toStates: @["Off"])
    ]
  )

  let generatedCode = generateCode(ts)

  # Write a complete file that includes types and generated code
  let fullCode = """
# Type definitions (normally in user code)
type
  Light = object
    brightness: int
  Off = distinct Light
  On = distinct Light

# --- Generated code below ---
""" & generatedCode & """

# Test the generated code works
when isMainModule:
  let off = Off(Light(brightness: 0))
  doAssert off.state == fsOff

  let on = On(Light(brightness: 100))
  doAssert on.state == fsOn

  # Test union type accepts both
  proc describe(l: LightStates): string =
    case l.state
    of fsOff: "off"
    of fsOn: "on"

  doAssert describe(off) == "off"
  doAssert describe(on) == "on"

  echo "Generated code compiles and works!"
"""

  writeFile(testFile, fullCode)

  # Actually compile it - this is the CONSUMPTION test
  let (output, exitCode) = execCmdEx("nim c --hints:off " & testFile)

  if exitCode != 0:
    echo "Compilation failed:"
    echo output
    doAssert false, "Generated code failed to compile"

  # Run it to verify runtime behavior
  let compiled = testFile.changeFileExt(ExeExt)
  let (runOutput, runExitCode) = execCmdEx(compiled)

  if runExitCode != 0:
    echo "Execution failed:"
    echo runOutput
    doAssert false, "Generated code failed at runtime"

  doAssert "Generated code compiles and works!" in runOutput,
    "Expected success message in output"

  # Cleanup
  removeFile(testFile)
  removeFile(compiled)

  echo "generateCode compilation test passed"

# CONSUMPTION TEST: Verify branching code compiles
block testGenerateCodeBranchingCompiles:
  let tempDir = getTempDir()
  let testFile = tempDir / "test_codegen_branching.nim"

  let ts = ParsedTypestate(
    name: "Door",
    states: @["Locked", "Unlocked", "Open"],
    transitions: @[
      ParsedTransition(fromState: "Locked", toStates: @["Unlocked"]),
      ParsedTransition(fromState: "Unlocked", toStates: @["Locked", "Open"])
    ]
  )

  let generatedCode = generateCode(ts)

  let fullCode = """
type
  Door = object
    id: int
  Locked = distinct Door
  Unlocked = distinct Door
  Open = distinct Door

""" & generatedCode & """

when isMainModule:
  # Test branch type construction
  let unlocked = Unlocked(Door(id: 1))

  # Test constructor
  let result1 = toUnlockedResult(Locked(Door(id: 2)))
  doAssert result1.kind == uLocked

  let result2 = toUnlockedResult(Open(Door(id: 3)))
  doAssert result2.kind == uOpen

  # Test -> operator
  let result3 = UnlockedResult -> Locked(Door(id: 4))
  doAssert result3.kind == uLocked

  # Test pattern matching
  case result3.kind
  of uLocked:
    doAssert result3.locked.Door.id == 4
  of uOpen:
    doAssert false, "Should be locked"

  echo "Branching code compiles and works!"
"""

  writeFile(testFile, fullCode)

  let (output, exitCode) = execCmdEx("nim c --hints:off " & testFile)

  if exitCode != 0:
    echo "Compilation failed:"
    echo output
    doAssert false, "Generated branching code failed to compile"

  let compiled = testFile.changeFileExt(ExeExt)
  let (runOutput, runExitCode) = execCmdEx(compiled)

  if runExitCode != 0:
    echo "Execution failed:"
    echo runOutput
    doAssert false, "Generated branching code failed at runtime"

  doAssert "Branching code compiles and works!" in runOutput

  removeFile(testFile)
  removeFile(compiled)

  echo "generateCode branching compilation test passed"

echo "All CLI codegen tests passed"
