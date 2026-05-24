## Regression (v0.9.3 style-insensitive matching, Gemini round 4): the
## `raises` pragma detection in the `transition` macro path must be
## style-insensitive, per Nim's identifier rules (first character
## case-sensitive, subsequent characters case- and underscore-insensitive).
## Here a regular transition (NOT a destructor) declares a non-empty raises
## list spelled `rAises: [IOError]` (interior capital), which is the same
## identifier as `raises` — and which Nim itself accepts as the built-in
## `raises` pragma.
##
## With the fix, `eqIdent` recognizes the variant spelling, so the library's
## own non-empty-raises check fires with the "has non-empty raises list"
## message. Before the fix the pragma name was matched with raw `==` against
## `pragmaName`, so the variant spelling was silently ignored by the
## `transition`-macro detection. The `expects:` directive asserts the
## library's specific message fires (not merely that compilation fails for
## some unrelated reason).
# expects: "has non-empty raises list"
import ../../../src/typestates

type
  Machine = object
  On = distinct Machine
  Off = distinct Machine

typestate Machine:
  consumeOnTransition = false # Opt out for existing tests
  states On, Off
  transitions:
    Off -> On
    On -> Off

# Wrong: a regular transition declares a non-empty raises list, spelled with a
# style variant (`rAises`). The non-empty-raises check must still reject it via
# `eqIdent` matching.
proc turnOn(m: Off): On {.transition, rAises: [IOError].} =
  On(m.Machine)
