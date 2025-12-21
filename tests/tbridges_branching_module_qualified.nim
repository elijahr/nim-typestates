## Test branching transitions combined with module-qualified bridges
##
## This test verifies that:
## 1. Branching transitions work correctly (one source, multiple destinations)
## 2. Module-qualified bridge syntax works with branching
## 3. Different execution paths lead to correct destination states
## 4. Branch types are properly generated and usable

import std/strutils
import ../src/typestates

# Destination typestates for different outcomes
type
  SuccessLog = object
    message: string
    timestamp: int

  LogSuccess = distinct SuccessLog

typestate SuccessLog:
  consumeOnTransition = false
  states LogSuccess
  transitions:
    LogSuccess -> LogSuccess

type
  ErrorLog = object
    error: string
    code: int

  LogError = distinct ErrorLog

typestate ErrorLog:
  consumeOnTransition = false
  states LogError
  transitions:
    LogError -> LogError

# Source typestate with branching that bridges to different typestates
type
  Task = object
    id: int
    data: string

  TaskPending = distinct Task
  TaskRunning = distinct Task

typestate Task:
  consumeOnTransition = false
  states TaskPending, TaskRunning
  transitions:
    TaskPending -> TaskRunning
    # Branching transition within same typestate
    TaskRunning -> (TaskPending | TaskRunning) as TaskContinue
  bridges:
    # Bridges from TaskRunning to different log typestates
    # In real scenarios, these would be terminal states, but for testing
    # we demonstrate the module-qualified syntax
    TaskRunning -> SuccessLog.LogSuccess
    TaskRunning -> ErrorLog.LogError

# Regular transition
proc start(t: TaskPending): TaskRunning {.transition.} =
  TaskRunning(t.Task)

# Branching transition (stays in same typestate)
proc continueTask(t: TaskRunning, retry: bool): TaskContinue {.transition.} =
  if retry:
    return toTaskContinue(TaskPending(t.Task))
  else:
    return toTaskContinue(t)

# Bridge to success log
proc logSuccess(t: TaskRunning): LogSuccess {.transition.} =
  LogSuccess(
    SuccessLog(
      message: "Task " & $t.Task.id & " completed: " & t.Task.data, timestamp: 12345
    )
  )

# Bridge to error log
proc logError(t: TaskRunning, errorMsg: string): LogError {.transition.} =
  LogError(ErrorLog(error: errorMsg & " (task " & $t.Task.id & ")", code: 500))

# Test branching within typestate
block test_branching_transition:
  let task = TaskPending(Task(id: 1, data: "process"))
  let running = start(task)

  # Branch to retry (back to Pending)
  let retryBranch = continueTask(running, true)
  case retryBranch.kind
  of tTaskPending:
    let pending = retryBranch.taskPending
    doAssert pending.Task.id == 1
    echo "Branching transition to TaskPending works"
  of tTaskRunning:
    doAssert false, "Should have branched to TaskPending"

  # Branch to continue (stay in Running)
  let running2 = start(task)
  let continueBranch = continueTask(running2, false)
  case continueBranch.kind
  of tTaskRunning:
    let stillRunning = continueBranch.taskRunning
    doAssert stillRunning.Task.id == 1
    echo "Branching transition to TaskRunning works"
  of tTaskPending:
    doAssert false, "Should have stayed in TaskRunning"

# Test bridge to success log
block test_bridge_to_success:
  let task = TaskPending(Task(id: 2, data: "success-case"))
  let running = start(task)
  let success = logSuccess(running)

  doAssert "Task 2 completed" in success.SuccessLog.message
  doAssert success.SuccessLog.timestamp == 12345
  echo "Bridge to module-qualified SuccessLog.LogSuccess works"

# Test bridge to error log
block test_bridge_to_error:
  let task = TaskPending(Task(id: 3, data: "error-case"))
  let running = start(task)
  let error = logError(running, "Network timeout")

  doAssert "Network timeout" in error.ErrorLog.error
  doAssert "task 3" in error.ErrorLog.error
  doAssert error.ErrorLog.code == 500
  echo "Bridge to module-qualified ErrorLog.LogError works"

# Test complete workflow: start -> branch -> bridge
block test_complete_workflow:
  let task = TaskPending(Task(id: 4, data: "full-workflow"))
  let running = start(task)

  # Try continuing first
  let continued = continueTask(running, false)
  case continued.kind
  of tTaskRunning:
    # Now bridge to success
    let success = logSuccess(continued.taskRunning)
    doAssert "Task 4" in success.SuccessLog.message
    echo "Complete workflow (start -> branch -> bridge) works"
  of tTaskPending:
    doAssert false, "Unexpected branch outcome"

echo "All branching + module-qualified bridge tests passed"
