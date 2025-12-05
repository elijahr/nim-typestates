## Test: Unsealed typestate can be extended
import ../../../src/typestates

type
  Task = object
    name: string
  Todo = distinct Task
  InProgress = distinct Task
  Done = distinct Task
  Cancelled = distinct Task  # Added via extension

# Base typestate - explicitly unsealed
typestate Task:
  isSealed = false
  strictTransitions = false
  states Todo, InProgress, Done
  transitions:
    Todo -> InProgress
    InProgress -> Done

# Extension adds new state and transition
typestate Task:
  states Cancelled
  transitions:
    Todo -> Cancelled
    InProgress -> Cancelled

proc start(t: Todo): InProgress {.transition.} =
  InProgress(t.Task)

proc finish(t: InProgress): Done {.transition.} =
  Done(t.Task)

proc cancelTodo(t: Todo): Cancelled {.transition.} =
  Cancelled(t.Task)

proc cancelInProgress(t: InProgress): Cancelled {.transition.} =
  Cancelled(t.Task)

let todo = Todo(Task(name: "Test"))
let cancelled = todo.cancelTodo()
echo "unsealed_extend test passed"
