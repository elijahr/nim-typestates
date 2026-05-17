## Test (DT-013 backfill): two-arg `{.destructorTransition.}` SrcState
## does not match the attached object's initial state.
##
## DT-013 (§3.1.1 step 5) catches the foot-gun where a developer writes
## the attached object's type name as the SrcState in the two-arg form
## instead of the initial-state name. Prior to §3.7 being implemented,
## this fixture was not exercisable because no attachment registry was
## populated — destructors with attached-object params failed earlier
## with DT-006. Now that §3.7 lands, DT-013 is reachable.
# expects: "does not match the attached object's initial state"
# expects: "ScopeAlive"
# expects: "ScopeContext"
import ../../../src/typestates

type
  ScopeAlive = object
  ScopeDead = object

typestate ScopeContext:
  consumeOnTransition = false
  strictTransitions = false
  states ScopeAlive, ScopeDead
  initial:
    ScopeAlive
  terminal:
    ScopeDead
  transitions:
    ScopeAlive -> ScopeDead

# Attach. Initial state is ScopeAlive.
type AttachedScope {.ScopeContext: ScopeAlive.} = object
  inner: int

# DT-013 trap: SrcState is the attached object type name (`AttachedScope`)
# rather than the initial state (`ScopeAlive`). The compiler must flag
# this because the user almost certainly meant `ScopeAlive -> ScopeDead`.
proc `=destroy`(s: var AttachedScope)
    {.destructorTransition: AttachedScope -> ScopeDead.} =
  discard
