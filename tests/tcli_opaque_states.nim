## Integration tests: verify() runs the opaque-states lint and surfaces
## warnings on its result. Mirrors `tcli_verify_warnings.nim` style.

import std/[unittest, sequtils, strutils, os]
import ../src/typestates/cli

suite "CLI verify + opaque-states lint":
  test "bypass surfaces in result.warnings":
    let tempDir = getTempDir()
    let testFile = tempDir / "tcli_opaque_bypass.nim"
    writeFile(
      testFile,
      """
type
  Payment = object
    id: string
  Created = distinct Payment
  Authorized = distinct Payment
  Captured = distinct Payment

typestate Payment:
  opaqueStates = true
  states Created, Authorized, Captured
  initial Created
  transitions:
    Created -> Authorized
    Authorized -> Captured

let bad = Captured(Payment(id: "x"))
""",
    )
    let r = verify(@[testFile])
    # Tolerate other unrelated warnings; >= 1 bypass warning required.
    let bypassWarnings =
      r.warnings.filterIt("bypass of opaque state 'Captured'" in it.message)
    check bypassWarnings.len >= 1
    check r.warnings.anyIt("(typestate 'Payment')" in it.message)
    check r.warnings.anyIt("outside {.transition.} proc" in it.message)
    check r.errors.len == 0
    removeFile(testFile)

  test "no warnings without flag":
    let tempDir = getTempDir()
    let testFile = tempDir / "tcli_opaque_no_flag.nim"
    writeFile(
      testFile,
      """
type
  Payment = object
    id: string
  Created = distinct Payment
  Authorized = distinct Payment
  Captured = distinct Payment

typestate Payment:
  states Created, Authorized, Captured
  initial Created
  transitions:
    Created -> Authorized
    Authorized -> Captured

let bad = Captured(Payment(id: "x"))
""",
    )
    let r = verify(@[testFile])
    let bypassWarnings = r.warnings.filterIt("bypass of opaque state" in it.message)
    check bypassWarnings.len == 0
    check r.errors.len == 0
    removeFile(testFile)

  test "configuration warning surfaces when no initial states":
    let tempDir = getTempDir()
    let testFile = tempDir / "tcli_opaque_no_initial.nim"
    writeFile(
      testFile,
      """
type
  Payment = object
    id: string
  Created = distinct Payment
  Authorized = distinct Payment
  Captured = distinct Payment

typestate Payment:
  opaqueStates = true
  states Created, Authorized, Captured
  transitions:
    Created -> Authorized
    Authorized -> Captured
""",
    )
    let r = verify(@[testFile])
    check r.warnings.anyIt("but no initial states declared" in it.message)
    check r.warnings.anyIt("opaqueStates = true on typestate 'Payment'" in it.message)
    removeFile(testFile)
