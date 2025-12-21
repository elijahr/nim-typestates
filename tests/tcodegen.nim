import ../src/typestates

type
  File = object
    path: string

  Closed = distinct File
  Open = distinct File
  Errored = distinct File

typestate File:
  consumeOnTransition = false # Opt out for existing tests
  states Closed, Open, Errored
  transitions:
    Closed -> Open
    Open -> Closed

# Test generated enum exists
doAssert FileState is enum
doAssert fsClosed in {low(FileState) .. high(FileState)}
doAssert fsOpen in {low(FileState) .. high(FileState)}
doAssert fsErrored in {low(FileState) .. high(FileState)}

# Test state() procs
let c = Closed(File(path: "/tmp"))
doAssert c.state == fsClosed

echo "codegen enum test passed"

# Test generated union type
proc acceptsAnyState(f: FileStates): string =
  result = f.File.path

let o = Open(File(path: "/tmp/test"))
doAssert acceptsAnyState(o) == "/tmp/test"

echo "codegen union test passed"
