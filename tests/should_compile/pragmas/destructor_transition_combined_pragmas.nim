## Test (Pepper G3): destructorTransition combines correctly with other
## pragmas, including {.raises: [].} (explicit), {.skipCfgAnalysis.},
## and the standard `inline` hint pragma.
##
## This is the *scanner correctness* fixture: the {.skipCfgAnalysis.}
## detection MUST work via an AST walk of procDef.pragma (NOT via a CLI
## substring match of the pragma's stringified form, which would break
## on combined forms — see project memory
## `project_typestates_verify_substring_matcher`).
##
## If any combined-pragma form is mis-detected, this fixture either:
##   - Compiles when it shouldn't (e.g., scanner missed combined form)
##   - Fails to compile with a wrong message (e.g., raises clash)
import ../../../src/typestates

type
  Channel = object
    name: string

  OpenCh = distinct Channel
  ClosedCh = distinct Channel

typestate Channel:
  consumeOnTransition = false
  strictTransitions = false
  states OpenCh, ClosedCh
  initial:
    OpenCh
  terminal:
    ClosedCh
  transitions:
    OpenCh -> ClosedCh

# Combined: {.destructorTransition, raises: [], skipCfgAnalysis.}
proc `=destroy`(c: var OpenCh)
    {.destructorTransition, raises: [], skipCfgAnalysis.} =
  discard

verifyTypestates()
echo "destructor_transition_combined_pragmas ok"
