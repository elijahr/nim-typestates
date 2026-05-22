## Test (v0.9.3 transitionError, REGRESSION GUARD): when `transitionError`
## is OMITTED, the built-in `Undeclared transition: ...` diagnostic must
## be preserved byte-for-byte.
##
## This is the backwards-compatibility regression test: a v0.9.2-style
## broken transition declaration must produce the same diagnostic in
## v0.9.3 that it did in v0.9.2. Any drift indicates the substitution
## path leaked into the no-override case.
# expects: "Undeclared transition: OpenFile -> LockedFile"
# expects: "Typestate 'FileT' does not declare this transition"
# expects: "Hint: Add 'OpenFile -> LockedFile' to the transitions block"
import ../../../src/typestates

type
  FileT = object
  ClosedFile = distinct FileT
  OpenFile = distinct FileT
  LockedFile = distinct FileT
  ReleasedFile = distinct FileT

typestate FileT:
  states ClosedFile, OpenFile, LockedFile, ReleasedFile
  initial: ClosedFile
  terminal: ReleasedFile
  transitions:
    ClosedFile -> OpenFile
    OpenFile -> ReleasedFile
    LockedFile -> ReleasedFile

# Same broken transition as `transition_error_custom_message_fires.nim`
# but WITHOUT `transitionError:`. Built-in diagnostic must surface.
proc lockFile(f: OpenFile): LockedFile {.transition.} =
  LockedFile(f)
