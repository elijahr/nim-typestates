## F3: Runtime $ overload for leaf states (non-generic typestate).
import ../../../src/typestates

type
  File = object
    path: string

  Closed = distinct File
  Open = distinct File
  Errored = distinct File

typestate File:
  consumeOnTransition = false
  states Closed, Open, Errored
  transitions:
    Closed -> Open
    Open -> Closed
    Open -> Errored

proc open(f: Closed): Open {.transition.} =
  Open(File(f))

let c = Closed(File(path: "/tmp/x"))
doAssert $c == "Closed"

let o = c.open()
doAssert $o == "Open"

# Symmetry with state() enum:
doAssert $state(o) == "Open"

# Enum $ overload directly.
doAssert $fsClosed == "Closed"
doAssert $fsOpen == "Open"
doAssert $fsErrored == "Errored"

# $ on an independent state value.
let e = Errored(File(path: "/tmp/zz"))
doAssert $e == "Errored"

echo "dollar_overload test passed"
