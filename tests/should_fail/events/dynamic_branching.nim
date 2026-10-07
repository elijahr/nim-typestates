## Negative compile-time test: dynamic value branching inside transition handlers
## Must fail compilation/static analysis: transitions must not branch on dynamic payload values
# expects: "dynamic branching"
import ../../../src/typestates

type
  SatContext = object
  Listening = distinct SatContext
  Idle = distinct SatContext
  PipelineError = distinct SatContext

typestate SatFSM:
  states Listening, Idle, PipelineError
  events:
    ErrorOccurred(code: string)

  transitions:
    # Anti-pattern: dynamic if-expression based on payload variable
    (Listening, ErrorOccurred) -> (if code == "silent": Idle else: PipelineError)

verifyTypestates()
