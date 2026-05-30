## Regression (v0.9.3 style-insensitive matching, Gemini round 3): the
## `transitionError:` custom message must fire even when the pragma keyword is
## spelled with a non-canonical style. Here it is spelled `transitionerror:`
## (lowercase `e`), which per Nim's identifier rules is the same identifier as
## `transitionError`.
##
## Before the fix, the pragma name was matched case-sensitively, so the variant
## spelling was SILENTLY ignored and the proc fell back to the built-in
## `Undeclared transition: ...` diagnostic. The `expects:`/`rejects:`
## directives below assert the custom message now fires AND wholly replaces the
## built-in one — proving the silent fallback is fixed.
# expects: "Cannot lock an open file"
# rejects: "Undeclared transition"
import ../../../src/typestates

type
  FileT = object
  ClosedFile = distinct FileT
  OpenFile = distinct FileT
  LockedFile = distinct FileT
  ReleasedFile = distinct FileT

# Note: `OpenFile -> LockedFile` is intentionally OMITTED from the
# transitions block. The `lockFile` proc below declares that transition
# and must fail at pragma-expansion with the custom message.
typestate FileT:
  states ClosedFile, OpenFile, LockedFile, ReleasedFile
  initial:
    ClosedFile
  terminal:
    ReleasedFile
  transitions:
    ClosedFile -> OpenFile
    OpenFile -> ReleasedFile
    LockedFile -> ReleasedFile

proc lockFile(
    f: OpenFile
): LockedFile {.transition, transitionerror: "Cannot lock an open file".} =
  LockedFile(f)
