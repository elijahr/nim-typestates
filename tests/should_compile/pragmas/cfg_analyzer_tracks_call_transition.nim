## Test (CFG-001 negative — call-tracking, Finding #1 scope (a)): a bare
## call to a `{.transition.}`-marked proc whose source state matches a
## tracked local's current state advances the local to the registered
## destination. When the destination is terminal, the local is dropped
## from tracking and the exit edge accepts cleanly.
##
## Pattern exercised (the original Gemini CRITICAL false positive):
##
##   var f: Open
##   discard close(f)        # close is a registered transition Open -> Closed
##   # f no longer tracked; fall-through exit edge accepts.
##
## Pre-fix: the analyzer would falsely emit CFG-001 because nnkCall was
## not recognized as a state-advancing form.
import ../../../src/typestates

type
  File = object
    n: int

  Open = distinct File
  Closed = distinct File

typestate File:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Closed

proc close(f: sink Open): Closed {.transition.} =
  ## Registered transition consuming Open, producing terminal Closed.
  result = Closed(f.File)

proc useFile() {.notATransition.} =
  ## The pattern that pre-fix tripped CFG-001 even though the call
  ## semantically consumed the local to terminal.
  var f: Open
  discard close(f)

verifyTypestates()
echo "cfg_analyzer_tracks_call_transition ok"
