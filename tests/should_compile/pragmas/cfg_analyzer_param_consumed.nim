## Test (CFG-001 negative — typestated `var T` param consumed in body,
## round-2 Finding #2): a proc taking `var f: Open` pre-populates the
## analyzer's live-set with `f` at proc entry. When the body consumes
## `f` via a registered transition call, the local is dropped from
## tracking and the fall-through exit edge accepts cleanly.
##
## Pre-fix the analyzer initialized `LiveState` empty: typestate-bearing
## params were invisible. A proc that early-returned without touching the
## param silently passed analysis. Round-2 Finding #2 corrects this by
## capturing each `var T` typestate-bearing param at registration time
## into `RegisteredProc.typestatedParams` and pre-populating the live-set
## at proc entry. This fixture confirms the consume path works under the
## new pre-population.
import ../../../src/typestates

type
  Channel = object
    fd: int

  Open = distinct Channel
  Closed = distinct Channel

typestate Channel:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Closed

proc shutdown(c: sink Open): Closed {.transition.} =
  ## Registered transition consuming Open to terminal.
  result = Closed(c.Channel)

proc closeChannel(c: var Open) {.notATransition.} =
  ## `var Open` param pre-populates the analyzer's live-set under
  ## Finding #2. The body reassigns `c` to the registered destination
  ## (terminal) via `shutdown`, which the round-1 asgn handler treats as
  ## a re-binding to terminal — `c` is dropped from tracking. Fall-through
  ## exit edge then accepts cleanly.
  discard shutdown(c)

verifyTypestates()

var c: Open
closeChannel(c)
echo "cfg_analyzer_param_consumed ok"
