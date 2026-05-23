## Regression (v0.9.3 style-insensitive matching, Gemini round 3): the
## `raises` pragma detection in the `destructorTransition` path must be
## style-insensitive, per Nim's identifier rules (first character
## case-sensitive, subsequent characters case- and underscore-insensitive).
## Here the destructor declares a non-empty raises list spelled
## `rAises: [IOError]` (interior capital), which is the same identifier as
## `raises` — and which Nim itself accepts as the built-in `raises` pragma.
##
## With the fix, `eqIdent` recognizes the variant spelling, so the library's
## own DT-005 check fires with the custom "has non-empty raises list" message.
## Before the fix the pragma name was matched with raw `strVal ==`, so the
## variant spelling was silently ignored by the DT-005 detection. The
## `expects:` directive asserts the library's specific message fires (not
## merely that compilation fails for some unrelated reason).
# expects: "has non-empty raises list"
import ../../../src/typestates

type
  Buffer = object
    data: int

  Filled = distinct Buffer
  Drained = distinct Buffer

typestate Buffer:
  consumeOnTransition = false
  strictTransitions = false
  states Filled, Drained
  initial:
    Filled
  terminal:
    Drained
  transitions:
    Filled -> Drained

# Wrong: destructor declares a non-empty raises list, spelled with a style
# variant (`rAises`). DT-005 must still reject it via `eqIdent` matching.
proc `=destroy`(b: var Filled) {.destructorTransition, rAises: [IOError].} =
  discard
