## Test: {.skipCfgAnalysis.} marker template is recognized on transition
## and destructorTransition procs without raising any pragma error.
##
## Verifies:
## - skipCfgAnalysis is a valid pragma (template-pragma definition)
## - It combines with {.transition.} via comma syntax
## - It combines with {.destructorTransition.} via comma syntax
## - skipCfg flag is set on the corresponding RegisteredProc (indirectly
##   verified by lack of compile error; the CFG analyzer lands in 3.1.b.3
##   and will assert the flag's behavioral effect there)
import ../../../src/typestates

type
  Pipeline = object
    stage: int

  Pending = distinct Pipeline
  Running = distinct Pipeline
  Done = distinct Pipeline

typestate Pipeline:
  consumeOnTransition = false
  strictTransitions = false
  states Pending, Running, Done
  initial:
    Pending
  terminal:
    Done
  transitions:
    Pending -> Running
    Running -> Done

# Destructor must be declared BEFORE any code that materializes a Running
# value, otherwise Nim implicitly binds a default `=destroy` and our hook
# is rejected as a duplicate binding.
proc `=destroy`(r: var Running) {.destructorTransition, skipCfgAnalysis.} =
  discard

proc start(p: Pending): Running {.transition, skipCfgAnalysis.} =
  Running(p.Pipeline)

verifyTypestates()
echo "skip_cfg_analysis ok"
