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

proc open(f: Closed): Open {.transition.} =
  result = Open(f)

proc close(f: Open): Closed {.transition.} =
  result = Closed(f)

# Test usage
let f = Closed(File(path: "/tmp/test"))
let opened = f.open()
let closed = opened.close()

echo "transition pragma test passed"
