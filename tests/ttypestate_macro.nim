import ../src/nim_typestates

type
  File = object
    path: string
    handle: int

  Closed = distinct File
  Open = distinct File

typestate File:
  states Closed, Open
  transitions:
    Closed -> Open
    Open -> Closed

# If we got here, parsing succeeded
echo "typestate macro test passed"
