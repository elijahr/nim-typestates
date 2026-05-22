## Test (v0.9.3 transitionError): a `{.transition.}` proc declared with
## `transitionError: "Cannot lock an open file"` on an UNDECLARED
## transition surfaces the custom message verbatim AND fully replaces
## the built-in `Undeclared transition: ...` diagnostic.
##
## This is the primary regression: omitting the substitution would leave
## the built-in message in place; partial substitution would leak it.
## The `rejects:` directive enforces the wholesale replacement.
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
  initial: ClosedFile
  terminal: ReleasedFile
  transitions:
    ClosedFile -> OpenFile
    OpenFile -> ReleasedFile
    LockedFile -> ReleasedFile

proc lockFile(f: OpenFile): LockedFile
    {.transition, transitionError: "Cannot lock an open file".} =
  LockedFile(f)
