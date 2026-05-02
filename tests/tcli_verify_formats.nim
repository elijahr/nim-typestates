## Tests for v0.7 verify output formatters: JSON envelope and GitHub Actions
## workflow-command annotations.
##
## - JSON envelope: schemaVersion, errors[], warnings[], filesChecked,
##   transitionsChecked. Asserts field order on per-finding objects to catch
##   regressions if `std/json`'s `JObject` ever stops preserving insertion order.
## - GitHub format: ::severity file=path,line=N::message — with `%0A` for
##   newlines in the body and `%2C` for commas in the path parameter.

import std/[unittest, json, strutils]
import ../src/typestates/cli
import ../src/typestates/findings
import ../src/typestates/reachability

suite "verify --format output":
  test "github format basic":
    let f = mkError(
      fcUnmarkedProcStrict, "src/foo.nim", 42, "Unmarked proc on state 'Closed'"
    )
    check formatGitHub(f) ==
      "::error file=src/foo.nim,line=42::Unmarked proc on state 'Closed'"

  test "github format with hint encodes %0A":
    let f = mkWarning(
      fcUnreachableState, "", 0, "Dead state 'X'",
      "Unreachable from any initial state.\nInitial states: A",
    )
    let outStr = formatGitHub(f)
    check outStr ==
      "::warning::Dead state 'X'%0AUnreachable from any initial state.%0AInitial states: A"

  test "github format omits file= when path empty":
    let f = mkWarning(
      fcOpaqueStatesNoInitials, "", 0, "opaqueStates = true requires initial:"
    )
    check formatGitHub(f) == "::warning::opaqueStates = true requires initial:"

  test "github format encodes comma in path":
    let f = mkError(fcUnmarkedProcStrict, "src/with,comma.nim", 5, "x")
    check formatGitHub(f) == "::error file=src/with%2Ccomma.nim,line=5::x"

  test "github format file with line zero omits ,line=":
    # If a finding has a path but no line, the GitHub annotation should
    # still emit `file=` but skip `,line=0`.
    let f = mkWarning(fcOpaqueStateBypass, "src/foo.nim", 0, "msg")
    check formatGitHub(f) == "::warning file=src/foo.nim::msg"

  test "json format produces valid envelope with one error":
    let s = formatJson(@[mkError(fcUnmarkedProcStrict, "src/foo.nim", 10, "msg")], 1, 0)
    let j = parseJson(s)
    check j["schemaVersion"].getInt == 1
    check j["verifyResult"]["filesChecked"].getInt == 1
    check j["verifyResult"]["transitionsChecked"].getInt == 0
    check j["verifyResult"]["errors"].len == 1
    check j["verifyResult"]["errors"][0]["code"].getStr == "unmarked-proc-strict"
    check j["verifyResult"]["errors"][0]["path"].getStr == "src/foo.nim"
    check j["verifyResult"]["errors"][0]["line"].getInt == 10
    check j["verifyResult"]["errors"][0]["message"].getStr == "msg"
    check j["verifyResult"]["errors"][0]["hint"].getStr == ""
    check j["verifyResult"]["warnings"].len == 0

  test "json format produces valid envelope with one warning":
    let s = formatJson(
      @[mkWarning(fcOpaqueStateBypass, "src/bar.nim", 7, "msg", "hint")], 2, 5
    )
    let j = parseJson(s)
    check j["schemaVersion"].getInt == 1
    check j["verifyResult"]["filesChecked"].getInt == 2
    check j["verifyResult"]["transitionsChecked"].getInt == 5
    check j["verifyResult"]["errors"].len == 0
    check j["verifyResult"]["warnings"].len == 1
    check j["verifyResult"]["warnings"][0]["path"].getStr == "src/bar.nim"
    check j["verifyResult"]["warnings"][0]["line"].getInt == 7
    check j["verifyResult"]["warnings"][0]["code"].getStr == "opaque-state-bypass"
    check j["verifyResult"]["warnings"][0]["message"].getStr == "msg"
    check j["verifyResult"]["warnings"][0]["hint"].getStr == "hint"

  test "json format empty findings":
    let s = formatJson(@[], 0, 0)
    let j = parseJson(s)
    check j["schemaVersion"].getInt == 1
    check j["verifyResult"]["errors"].len == 0
    check j["verifyResult"]["warnings"].len == 0
    check j["verifyResult"]["filesChecked"].getInt == 0
    check j["verifyResult"]["transitionsChecked"].getInt == 0

  test "json format envelope starts with schemaVersion":
    # Field-order assertion at the envelope level: per design §6.3,
    # `{"schemaVersion":1,` must come first so a streaming consumer can
    # cheaply reject unknown versions.
    let s = formatJson(@[], 0, 0)
    check s.startsWith("{\"schemaVersion\":1,")

  test "json format finding field order":
    # Asserts std/json's OrderedTable insertion-order guarantee for JObject.
    # Per-finding object key order MUST be: path, line, code, message, hint.
    # If a future Nim version drops that guarantee this test surfaces it.
    let s = formatJson(
      @[mkError(fcUnmarkedProcStrict, "src/foo.nim", 10, "msg", "hint")], 1, 0
    )
    let firstObjStart = s.find("{\"path\"")
    check firstObjStart >= 0
    let pathIdx = s.find("\"path\"", firstObjStart)
    let lineIdx = s.find("\"line\"", firstObjStart)
    let codeIdx = s.find("\"code\"", firstObjStart)
    let msgIdx = s.find("\"message\"", firstObjStart)
    let hintIdx = s.find("\"hint\"", firstObjStart)
    check pathIdx < lineIdx
    check lineIdx < codeIdx
    check codeIdx < msgIdx
    check msgIdx < hintIdx

  test "schema version constant":
    check SchemaVersion == 1

suite "reachability round-trip vs v0.6 formatFinding":
  # Property: formatHuman(toFinding(rf, initials, terminals)) MUST equal the
  # v0.6 formatFinding(rf, initials, terminals) output verbatim. This is the
  # safety net for migration false-greens — if any kind drifts, the test
  # diff surfaces it.
  #
  # The reference strings below are copied from `reachability.nim:formatFinding`
  # before the v0.7 refactor. The shim still exists in `reachability.nim` and
  # is also asserted equal to the test-local v0.6 reference for double-check.

  let initials = @["A", "B"]
  let terminals = @["Z"]

  proc v06Reference(f: ReachabilityFinding): string =
    case f.kind
    of rfDead:
      "Dead state '" & f.stateName & "' in typestate '" & f.typestateName & "'\n" &
        "  Unreachable from any initial state.\n" & "  Initial states: " &
        initials.join(", ") & "\n" & "  Hint: add a transition INTO '" & f.stateName &
        "', remove it from `states`, or declare it `initial:`."
    of rfTrap:
      "Trap state '" & f.stateName & "' in typestate '" & f.typestateName & "'\n" &
        "  Reachable, but cannot reach any terminal state.\n" & "  Terminal states: " &
        terminals.join(", ") & "\n" & "  Hint: add a transition out of '" & f.stateName &
        "' that reaches a terminal, or declare '" & f.stateName & "' itself terminal."
    of rfOrphan:
      "Orphan state '" & f.stateName & "' in typestate '" & f.typestateName & "'\n" &
        "  No incoming transitions and not declared `initial:`.\n" &
        "  Hint: declare it `initial:` or add a transition INTO it."
    of rfNoEntryPoint:
      "Typestate '" & f.typestateName & "' has no entry point.\n" &
        "  Every state has at least one incoming transition (graph is one or more cycles).\n" &
        "  Hint: declare an `initial:` block."

  test "rfDead round-trip":
    let rf =
      ReachabilityFinding(kind: rfDead, stateName: "Frozen", typestateName: "Door")
    check formatHuman(toFinding(rf, initials, terminals)) == v06Reference(rf)

  test "rfTrap round-trip":
    let rf =
      ReachabilityFinding(kind: rfTrap, stateName: "Stuck", typestateName: "Door")
    check formatHuman(toFinding(rf, initials, terminals)) == v06Reference(rf)

  test "rfOrphan round-trip":
    let rf =
      ReachabilityFinding(kind: rfOrphan, stateName: "Iso", typestateName: "Door")
    check formatHuman(toFinding(rf, initials, terminals)) == v06Reference(rf)

  test "rfNoEntryPoint round-trip":
    let rf =
      ReachabilityFinding(kind: rfNoEntryPoint, stateName: "", typestateName: "Cycle")
    check formatHuman(toFinding(rf, initials, terminals)) == v06Reference(rf)

  test "v0.6 shim formatFinding still matches reference (all kinds)":
    # If the shim was refactored away and the test relies on toFinding alone,
    # this test is just a paranoia double-check. If the shim still exists
    # (current code), this guards against shim drift across every
    # ReachabilityFindingKind, not just rfDead.
    let rfDeadF =
      ReachabilityFinding(kind: rfDead, stateName: "Frozen", typestateName: "Door")
    check formatFinding(rfDeadF, initials, terminals) == v06Reference(rfDeadF)
    let rfTrapF =
      ReachabilityFinding(kind: rfTrap, stateName: "Stuck", typestateName: "Door")
    check formatFinding(rfTrapF, initials, terminals) == v06Reference(rfTrapF)
    let rfOrphanF =
      ReachabilityFinding(kind: rfOrphan, stateName: "Iso", typestateName: "Door")
    check formatFinding(rfOrphanF, initials, terminals) == v06Reference(rfOrphanF)
    let rfNoEntryF =
      ReachabilityFinding(kind: rfNoEntryPoint, stateName: "", typestateName: "Cycle")
    check formatFinding(rfNoEntryF, initials, terminals) == v06Reference(rfNoEntryF)
