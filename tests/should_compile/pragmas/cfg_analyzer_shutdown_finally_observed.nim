## Test (G1 cross-check, E1 audit): the observed nim-debra/manager.nim:62
## `shutdown` pattern — a {.transition.}-marked proc that wraps a destructor-
## raising operation in `try: ...; except Exception: discard`, annotated
## with `{.skipCfgAnalysis.}` per the E1 cross-repo audit's escape-hatch
## recommendation (1 of 50 audited procs).
##
## Sources:
##   - design-destructortransition-cfg-analyzer-20260516.md §2.5 / §3.6
##     ("E1 cross-repo audit" — 49 SAFE + 1 requires skipCfgAnalysis)
##   - nim-debra/src/debra/typestates/manager.nim:57-80 (verbatim shape:
##     for-loop with try/except-discard around a sink-consuming call;
##     proc marked `{.transition, skipCfgAnalysis.}`)
##
## The fixture MUST compile clean. Per the audit, the analyzer's pessimism
## would otherwise reject this shape (false positive) BECAUSE the body's
## sink-consumed value escapes analyzer visibility across the for-loop +
## try boundary. `{.skipCfgAnalysis.}` is the documented escape hatch.
import ../../../src/typestates

type
  Limbo = object
    n: int

  Active = distinct Limbo
  Reclaimed = distinct Limbo

typestate Limbo:
  consumeOnTransition = false
  strictTransitions = false
  states Active, Reclaimed
  initial:
    Active
  terminal:
    Reclaimed

# Destructor for Active that may itself raise — mirrors nim-debra's
# reclaimBag behavior where the destructor chain may surface exceptions.
proc `=destroy`(a: var Active) {.destructorTransition.} =
  discard

type
  Manager = object
    n: int

  ManagerReady = distinct Manager
  ManagerShutdown = distinct Manager

typestate Manager:
  consumeOnTransition = false
  strictTransitions = false
  states ManagerReady, ManagerShutdown
  initial:
    ManagerReady
  terminal:
    ManagerShutdown
  transitions:
    ManagerReady -> ManagerShutdown

proc reclaim(a: sink Active) =
  discard a

proc shutdown(m: sink ManagerReady): ManagerShutdown {.transition, skipCfgAnalysis.} =
  ## Verbatim shape of nim-debra/manager.nim:62 `shutdown` per E1 audit.
  ## A for-loop iterates a worklist; each iteration wraps a sink-consuming
  ## call in `try: <call>; except Exception: discard` to tolerate destructor
  ## exceptions during shutdown. `{.skipCfgAnalysis.}` is REQUIRED per the
  ## audit because the analyzer would otherwise emit a false positive on
  ## the cross-boundary sink consumption.
  for _ in 0 .. 1:
    var live: Active
    try:
      reclaim(live)
    except Exception:
      discard
  result = ManagerShutdown(m)

verifyTypestates()
echo "cfg_analyzer_shutdown_finally_observed ok"
