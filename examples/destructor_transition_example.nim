## Destructor-Transition Example
##
## Demonstrates the v0.9.0 `{.destructorTransition.}` pragma: a Nim
## `=destroy` hook that performs the terminal transition of a typestate.
##
## With this pattern, the v0.9.0 CFG analyzer recognizes that any local
## of the typestate's source-state type is auto-consumed at every scope
## exit (return, raise, fall-through). Early-return code shapes that
## would otherwise leak the typestate compile cleanly.

import ../src/typestates

type
  FileHandle = object
    fd: int

  Open = distinct FileHandle
  Closed = distinct FileHandle

typestate FileLifecycle:
  consumeOnTransition = false
  strictTransitions = false
  states Open, Closed
  initial:
    Open
  terminal:
    Closed
  transitions:
    Open -> Closed

proc `=destroy`(f: var Open) {.destructorTransition.} =
  ## Bridges Open -> Closed. Nim injects this destructor at every scope
  ## exit that leaves an `Open` local in scope; the CFG analyzer treats
  ## the local as "will reach terminal via the destructor" and accepts
  ## return/raise/fall-through without an explicit consuming call.
  echo "  [FILE] destructor closing fd ", f.FileHandle.fd

proc consume(o: sink Open): Closed {.transition.} =
  ## Explicit terminal transition. Hands the local off to the caller as
  ## a Closed value; the destructor does NOT fire on `o` because `sink`
  ## moves ownership out.
  echo "  [FILE] explicit close of fd ", o.FileHandle.fd
  result = Closed(o.FileHandle)

proc run(early: bool) =
  ## Owns an `Open` local. On the early-return path the local is NOT
  ## explicitly consumed; the destructor fires automatically and the
  ## CFG analyzer is satisfied (the local has a destructorTransition
  ## bridging to a terminal state).
  var aux = Open(FileHandle(fd: 7))
  if early:
    echo "  [run] early return — destructor will close aux"
    return
  let closed = consume(move aux)
  echo "  [run] explicit close result fd=", closed.FileHandle.fd

verifyTypestates()

when isMainModule:
  echo "=== Destructor-Transition Demo ==="
  echo "1. Early-return path:"
  run(early = true)
  echo "2. Full path:"
  run(early = false)
  echo "=== Done ==="
