# Typestate with wildcard transitions

type
  Resource = object
    id: int

  Active = distinct Resource
  Paused = distinct Resource
  Stopped = distinct Resource

typestate Resource:
  states Active, Paused, Stopped
  transitions:
    Active -> Paused
    Paused -> Active
    * ->Stopped
