## Test (TA-003): the initial state is a terminal state of the
## typestate.
##
## A type whose initial state is terminal would start its life with no
## valid transitions — a useless and almost certainly accidental shape.
## The TA-003 diagnostic must explain why this is forbidden.
# expects: "initial state"
# expects: "terminal state"
# expects: "JobState"
import ../../../src/typestates

type
  JobPending = object
  JobDone = object

typestate JobState:
  consumeOnTransition = false
  strictTransitions = false
  states JobPending, JobDone
  initial:
    JobPending
  terminal:
    JobDone
  transitions:
    JobPending -> JobDone

# JobDone is terminal — using it as the initial state is forbidden.
type Worker {.JobState: JobDone.} = object
  id: int
