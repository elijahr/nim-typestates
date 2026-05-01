## F5: A transition with extra (non-state) parameters must still receive a
## state-aware decoy that preserves the rest of the signature.
##
## `close(a: Active, reason: string)` expects an `Active` account. Calling it
## with a `Frozen` account must fail with the F5 tailored error, and the
## decoy must also accept the trailing `reason: string` parameter.
# expects: "Cannot call 'close' on a value in state 'Frozen'. Expected 'Active'."
import ../../../src/typestates

type
  Account = object
    balance: int

  Active = distinct Account
  Frozen = distinct Account
  Closed = distinct Account

typestate Account:
  consumeOnTransition = false
  strictTransitions = false
  states Active, Frozen, Closed
  transitions:
    Active -> Frozen
    Frozen -> Active
    Active -> Closed

proc close(a: sink Active, reason: string): Closed {.transition.} =
  Closed(Account(a))

proc unfreeze(a: sink Frozen): Active {.transition.} =
  Active(Account(a))

verifyTypestates()

let f = Frozen(Account(balance: 100))
discard f.close("manual") # WRONG STATE — should fail with the F5 tailored error
