## D1 regression — variant 2/4: ident-bound arm head in a generic proc.
##
## Companion to match_macro_nnksym_in_generic_proc.nim — same overall
## scenario (branching union, generic proc body) but the arm-head binding
## is shadowed locally so it arrives as `nnkIdent` (or `nnkOpenSymChoice`)
## rather than `nnkSym`. Covers the "other half" of the v0.7.0 bug-class:
## the macro must accept BOTH ident and sym arm heads to be robust.
import ../../../src/typestates

type
  Msg = object
    payload: string

  Pending = distinct Msg
  Delivered = distinct Msg
  Dropped = distinct Msg
  Done = distinct Msg
  Logged = distinct Msg

typestate Msg:
  states Pending, Delivered, Dropped, Done, Logged
  transitions:
    Pending -> (Delivered | Dropped) as Outcome
    Delivered -> Done
    Dropped -> Logged

proc resolve(m: sink Pending): Outcome {.transition.} =
  if Msg(m).payload.len > 0:
    Outcome(kind: oDelivered, delivered: Delivered(Msg(m)))
  else:
    Outcome(kind: oDropped, dropped: Dropped(Msg(m)))

proc complete(d: sink Delivered): Done {.transition.} =
  Done(Msg(d))

proc logIt(x: sink Dropped): Logged {.transition.} =
  Logged(Msg(x))

# Use a generic proc that introduces local shadowing names matching
# the binding identifiers, increasing the chance that sema produces
# nnkOpenSymChoice / nnkIdent for the arm head rather than a plain sym.
proc routeWithShadow[T](m: sink Pending, ok: T, bad: T): T =
  # local names overlap with arm bindings (`d`, `x`) — exercises ident path
  let d {.used.}: int = 0
  let x {.used.}: int = 0
  var outcome = m.resolve()
  var label: T
  match outcome:
    Delivered(d):
      let done = d.complete()
      doAssert Msg(done).payload.len > 0
      label = ok
    Dropped(x):
      let logged = x.logIt()
      doAssert Msg(logged).payload.len == 0
      label = bad
  label

doAssert routeWithShadow[string](
  Pending(Msg(payload: "hi")), "delivered", "dropped"
) == "delivered"
doAssert routeWithShadow[string](
  Pending(Msg(payload: "")), "delivered", "dropped"
) == "dropped"
echo "match_macro_nnkident_in_generic_proc test passed"
