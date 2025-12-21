# Typestate with flags

type
  Task = object
    name: string

  Pending = distinct Task
  Running = distinct Task
  Done = distinct Task

typestate Task:
  strictTransitions = false
  states Pending, Running, Done
  transitions:
    Pending -> Running
    Running -> Done
