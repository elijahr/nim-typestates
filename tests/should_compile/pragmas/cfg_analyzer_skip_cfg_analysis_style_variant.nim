## Regression (v0.9.3 style-insensitive matching, Gemini round 3): the
## `skipCfgAnalysis` pragma must be recognized under a non-canonical style.
## Here it is spelled `skipcfganalysis` (all lowercase), which per Nim's
## identifier rules is the same identifier as `skipCfgAnalysis`.
##
## The body below would OTHERWISE fire CFG-001 at fall-through (a non-terminal
## `Held` local with no destructor) — see the negative-control
## `tests/should_fail/pragmas/cfg_analyzer_skip_cfg_analysis_required.nim`,
## whose IDENTICAL body fails without any opt-out pragma. So this fixture
## compiling PROVES the variant-spelled pragma actually took effect; before the
## fix the pragma name was matched case-sensitively and the variant spelling
## was silently ignored, leaving CFG-001 to fire.
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

proc finish(r: sink Held): Released {.transition, skipcfganalysis.} =
  ## Body declares a non-terminal `s: Held` with no destructor; fall-through
  ## would normally fire CFG-001. The style-variant `{.skipcfganalysis.}`
  ## must bypass the check.
  var s {.used.}: Held
  result = Released(r)

verifyTypestates()
echo "cfg_analyzer_skip_cfg_analysis_style_variant ok"
