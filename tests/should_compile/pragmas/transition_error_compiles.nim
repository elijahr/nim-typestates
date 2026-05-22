## Test (v0.9.3 transitionError): a `{.transition.}` proc declared with
## `transitionError: "custom msg"` on a VALID transition compiles cleanly.
##
## The sibling-pragma form `{.transition, transitionError: "msg".}` is the
## canonical syntax. The custom error string is harvested at
## pragma-expansion time but never emitted on a valid declaration —
## verification here is that the macro accepts the sibling pragma without
## interfering with normal validation.
import ../../../src/typestates

type
  Pipe = object
  PipeOpen = distinct Pipe
  PipeClosed = distinct Pipe

typestate Pipe:
  states PipeOpen, PipeClosed
  initial: PipeOpen
  terminal: PipeClosed
  transitions:
    PipeOpen -> PipeClosed

proc closePipe(p: PipeOpen): PipeClosed
    {.transition, transitionError: "Pipe must close exactly once".} =
  PipeClosed(p)

verifyTypestates()
echo "transition_error_compiles ok"
