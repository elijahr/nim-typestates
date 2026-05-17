## Test (skipCfgAnalysis opt-out — positive half): a proc whose body would
## OTHERWISE fail CFG-001 (typestate-bearing local in non-terminal state
## with no destructor at fall-through) compiles cleanly when annotated
## with `{.skipCfgAnalysis.}`. The companion `cfg_analyzer_skip_cfg_analysis_required.nim`
## fixture verifies the same body WITHOUT the pragma DOES fail CFG-001,
## proving the pragma is what's disabling the check (not some other
## analyzer concession).
##
## Per the 3.1.b.2 registration wiring + 3.1.b.5b step 8 verification:
## `RegisteredProc.skipCfg = true` causes `runCfgAnalyzer` to skip the
## per-proc body walk entirely. The body's exit-edge violations are
## silently tolerated.
import ../../../src/typestates

type
  Resource = object
    n: int

  Held = distinct Resource
  Released = distinct Resource

typestate Resource:
  consumeOnTransition = false
  strictTransitions = false
  states Held, Released
  initial:
    Held
  terminal:
    Released
  transitions:
    Held -> Released

proc finish(r: sink Held): Released
    {.transition, skipCfgAnalysis.} =
  ## Body declares a non-terminal `s: Held` with no destructor; fall-through
  ## would normally fire CFG-001. `{.skipCfgAnalysis.}` bypasses the check.
  var s {.used.}: Held
  result = Released(r)

verifyTypestates()
echo "cfg_analyzer_skip_cfg_analysis_opts_out ok"
