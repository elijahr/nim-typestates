import ../src/typestates

type
  File = object
    path: string
    data: string

  Closed = distinct File
  Open = distinct File

typestate File:
  consumeOnTransition = false # Opt out for existing tests
  states Closed, Open
  transitions:
    Closed -> Open
    Open -> Closed

proc open(f: Closed): Open {.transition.} =
  result = Open(f)

proc close(f: Open): Closed {.transition.} =
  result = Closed(f)

# This has side effects but doesn't change state
proc write(f: Open, data: string) {.notATransition.} =
  # In real code, would write to file
  discard

# Pure function - no annotation needed
func path(f: Open): string =
  f.File.path

echo "notATransition test passed"
