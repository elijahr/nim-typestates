## Compile-time capability probe for Nim issue #25341.
##
## The bug: for ARC/ORC/AtomicARC/Hooks memory managers, the compiler generates
## invalid C code (``m_type`` field access on plain objects) for lifecycle hooks
## on distinct types derived from generic objects with ``static`` parameters.
## See: https://github.com/nim-lang/Nim/issues/25341
##
## A version-triple check (``Nim < 2.2.8``) was historically used to gate the
## library's error, but is unreliable: a binary reporting a given version may
## or may not actually contain the fix (backport timing, custom builds, Nim
## package-manager binaries that predate the tag). This module replaces the
## version check with a real capability probe that invokes ``nim c`` against
## the exact multi-file repro from the upstream issue and inspects the C
## compiler output.
##
## The probe is:
##
## - **Lazy**: runs only when the typestate macro encounters conditions that
##   would trigger the bug (distinct generic with ``static`` + ``consumeOnTransition = true``
##   + not inheriting from ``RootObj``). Users whose typestates don't hit
##   those conditions pay zero cost.
## - **Cached**: the result is stored in a ``{.compileTime.}`` var so at most
##   one probe runs per ``nim c`` invocation, regardless of how many typestates
##   use the risky pattern.
## - **Defensive**: if the probe can't run (``nim`` missing from PATH,
##   filesystem errors, unexpected compiler output), the probe returns
##   ``false`` (assume buggy), which matches the library's historical safe
##   default.

import std/[os, strutils]

# Multi-module repro reproduced from https://github.com/nim-lang/Nim/issues/25341.
# The bug requires the ``=copy`` hook to be lifted across module boundaries by
# two separate consumer modules (one via ``discard``, one via global variable
# assignment), so a single-file ``compiles()`` probe cannot detect it.

const probeModuleSrc = """
type
  TypestatesBugProbeBase*[N: static int] = object
    value*: int
  TypestatesBugProbeDistinct1*[N: static int] = distinct TypestatesBugProbeBase[N]
  TypestatesBugProbeDistinct2*[N: static int] = distinct TypestatesBugProbeBase[N]

proc `=copy`*[N: static int](
    dest: var TypestatesBugProbeDistinct2[N], src: TypestatesBugProbeDistinct2[N]
) {.error: "no".}

proc tpsBugProbeMake1*[N: static int](): TypestatesBugProbeDistinct1[N] =
  TypestatesBugProbeDistinct1[N](TypestatesBugProbeBase[N](value: 0))

proc tpsBugProbeMake2*[N: static int](
    u: sink TypestatesBugProbeDistinct1[N]
): TypestatesBugProbeDistinct2[N] =
  TypestatesBugProbeDistinct2[N](TypestatesBugProbeBase[N](u))
"""

const probeASrc = """
import ./tps_bp_module

proc tpsBugProbeA*() =
  discard tpsBugProbeMake1[4]().tpsBugProbeMake2()
"""

const probeBSrc = """
import ./tps_bp_module

var tpsBugProbeGlobal: TypestatesBugProbeDistinct2[4]

proc tpsBugProbeB*() =
  tpsBugProbeGlobal = tpsBugProbeMake1[4]().tpsBugProbeMake2()
"""

const probeMainSrc = """
import ./tps_bp_a, ./tps_bp_b
tpsBugProbeA()
tpsBugProbeB()
"""

var
  probeHasRun {.compileTime.}: bool = false
  probeCachedClean {.compileTime.}: bool = false

proc runProbe(): bool {.compileTime.} =
  ## Run the multi-file repro through ``nim c`` via ``gorgeEx``.
  ##
  ## :returns: ``true`` if the compiler produced a working binary (fix
  ##   present); ``false`` if the C compiler rejected the generated code
  ##   with the ``m_type`` error (bug present); ``false`` for any other
  ##   failure mode (defensive default).
  let probeDir = getTempDir() / "nim_typestates_probe_25341"

  # Idempotent setup: wipe any prior probe scratch and recreate.
  # Using staticExec because std/os mutation procs aren't available at NimVM.
  discard staticExec(
    "rm -rf " & quoteShell(probeDir) & " && mkdir -p " & quoteShell(probeDir)
  )

  writeFile(probeDir / "tps_bp_module.nim", probeModuleSrc)
  writeFile(probeDir / "tps_bp_a.nim", probeASrc)
  writeFile(probeDir / "tps_bp_b.nim", probeBSrc)
  writeFile(probeDir / "tps_bp_main.nim", probeMainSrc)

  let cmd =
    "nim c --mm:orc --hints:off --warnings:off " & "--nimcache:" &
    quoteShell(probeDir / "cache") & " " & quoteShell(probeDir / "tps_bp_main.nim")

  let (output, exitCode) = gorgeEx(cmd, "", "typestates_probe_25341")

  # Best-effort cleanup; if it fails we don't care, the next probe will rm -rf.
  discard staticExec("rm -rf " & quoteShell(probeDir))

  # Happy path: probe compiled cleanly. Fix is present.
  if exitCode == 0:
    return true

  # Known-buggy signature: C compiler rejected ``m_type`` access.
  if output.contains("m_type"):
    return false

  # Inconclusive: nim not in PATH, unrelated failure, etc. Default to "assume
  # buggy" so we preserve the historical safe behavior of the version gate.
  return false

proc compilerHasFix25341*(): bool {.compileTime.} =
  ## Returns ``true`` if the current Nim compiler has the fix for issue
  ## #25341 (``m_type`` access bug for distinct generic hooks).
  ##
  ## Lazy + cached: the first call runs the probe; subsequent calls within
  ## the same ``nim c`` invocation return the cached result.
  if not probeHasRun:
    probeHasRun = true
    probeCachedClean = runProbe()
  probeCachedClean
