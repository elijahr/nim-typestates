## Test (skipCfgAnalysis opt-out — negative half): IDENTICAL body to
## `cfg_analyzer_skip_cfg_analysis_opts_out.nim` but WITHOUT the
## `{.skipCfgAnalysis.}` pragma. Proves the pragma — not some incidental
## analyzer concession — is what disables the check. CFG-001 fires at
## fall-through.
##
## Per Appendix B CFG-001: "Typestate-bearing local `<name>` has not
## reached a terminal state at this `<edge>`. Current state: `<type>` in
## typestate `<graph>`. Terminal states: `<list>`."
# expects: "has not reached a terminal state at this fall-through"
# expects: "Held"
# expects: "Released"
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

proc finish(r: sink Held): Released {.transition.} =
  ## Identical body to the paired should_compile fixture; only difference
  ## is missing `{.skipCfgAnalysis.}`. CFG-001 fires at fall-through.
  var s {.used.}: Held
  result = Released(r)

verifyTypestates()
