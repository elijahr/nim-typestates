import ../src/typestates

type
  File = object
  Closed = distinct File
  Open = distinct File

typestate File:
  consumeOnTransition = false  # Opt out for existing tests
  states Closed, Open
  transitions:
    Closed -> Open
    Open -> Closed

proc open(f: Closed): Open {.transition.} =
  result = Open(f)

proc close(f: Open): Closed {.transition.} =
  result = Closed(f)

proc read(f: Open): string {.notATransition.} =
  result = "data"

# Verify all is well
verifyTypestates()

echo "verify test passed"
