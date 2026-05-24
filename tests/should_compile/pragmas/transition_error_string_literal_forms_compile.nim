## Test (v0.9.3 M1): `transitionError` accepts every static string-literal
## form, not just the plain `nnkStrLit`. A user writing a multi-line error
## message naturally reaches for a triple-quoted (`"""..."""`,
## `nnkTripleStrLit`) literal, and a message containing backslashes for a
## raw (`r"..."`, `nnkRStrLit`) literal. Both are compile-time constants the
## `transitionError` extractor must accept; before the M1 fix only plain
## string literals were accepted and these forms hit the
## "must be a static string literal" error at declaration time.
##
## On a VALID transition the harvested message is never emitted, so the
## assertion of this fixture is simply that BOTH literal forms compile and
## the program runs — proving the widened accept set
## `{nnkStrLit, nnkRStrLit, nnkTripleStrLit}` works end to end.
import ../../../src/typestates

type
  Pipe = object
  PipeOpen = distinct Pipe
  PipeHalf = distinct Pipe
  PipeClosed = distinct Pipe

typestate Pipe:
  states PipeOpen, PipeHalf, PipeClosed
  initial:
    PipeOpen
  terminal:
    PipeClosed
  transitions:
    PipeOpen -> PipeHalf
    PipeHalf -> PipeClosed

# Triple-quoted (multi-line) message: nnkTripleStrLit
proc halfClose(p: PipeOpen): PipeHalf {.
    transition,
    transitionError: """Pipe is open.
Call halfClose() before closePipe();
a pipe must pass through the half-closed state."""
.} =
  PipeHalf(p)

# Raw-string message: nnkRStrLit (backslashes survive verbatim)
proc closePipe(
    p: PipeHalf
): PipeClosed {.
    transition, transitionError: r"Pipe path: C:\tmp\pipe must be closed once"
.} =
  PipeClosed(p)

verifyTypestates()
echo "transition_error_string_literal_forms_compile ok"
