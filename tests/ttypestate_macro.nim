import ../src/typestates

type
  File = object
    path: string
    handle: int

  Closed = distinct File
  Open = distinct File

typestate File:
  consumeOnTransition = false # Opt out for existing tests
  states Closed, Open
  transitions:
    Closed -> Open
    Open -> Closed

# If we got here, parsing succeeded
echo "typestate macro test passed"
