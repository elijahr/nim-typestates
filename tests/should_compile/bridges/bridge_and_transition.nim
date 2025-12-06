## Test: State with both internal transition and bridge
import ../../../src/typestates

type
  Pipeline = object
    stage: int
  Stage1 = distinct Pipeline
  Stage2 = distinct Pipeline
  Complete = distinct Pipeline

  Archive = object
  Archived = distinct Archive

typestate Archive:
  consumeOnTransition = false  # Opt out for existing tests
  strictTransitions = false
  states Archived

typestate Pipeline:
  consumeOnTransition = false  # Opt out for existing tests
  strictTransitions = false
  states Stage1, Stage2, Complete
  transitions:
    Stage1 -> Stage2
    Stage2 -> Complete
    Complete -> Stage1  # Can restart
  bridges:
    Complete -> Archive.Archived  # Or archive when done

proc advance1(p: Stage1): Stage2 {.transition.} =
  var pipe = p.Pipeline
  pipe.stage = 2
  Stage2(pipe)

proc advance2(p: Stage2): Complete {.transition.} =
  var pipe = p.Pipeline
  pipe.stage = 3
  Complete(pipe)

proc restart(p: Complete): Stage1 {.transition.} =
  Stage1(Pipeline(stage: 1))

proc archive(p: Complete): Archived {.transition.} =
  Archived(Archive())

let p = Stage1(Pipeline(stage: 1))
let s2 = p.advance1()
let complete = s2.advance2()

# Can either restart (transition) or archive (bridge)
let restarted = complete.restart()
doAssert restarted.Pipeline.stage == 1

let p2 = Stage1(Pipeline(stage: 1))
let complete2 = p2.advance1().advance2()
let archived = complete2.archive()

echo "bridge_and_transition test passed"
