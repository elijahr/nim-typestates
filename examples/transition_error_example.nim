## Transition-Error Pragma Example (v0.9.3)
##
## Demonstrates the v0.9.3 `{.transitionError: "msg".}` sibling pragma:
## a way for typestate authors to pin a custom error string that the
## Nim compiler emits verbatim when a transition declaration is
## invalid.
##
## This example DOES NOT trigger the custom error — the transitions
## declared are all valid. It exists to show the **shape** of the
## sibling-pragma syntax (the canonical form is
## `{.transition, transitionError: "msg".}`) and to confirm the
## feature compiles cleanly when the transition is well-formed.
##
## To see the custom error fire, see the negative tests:
##   tests/should_fail/pragmas/transition_error_custom_message_fires.nim
##   tests/should_fail/pragmas/destructor_transition_error_custom_message_fires.nim
##
## **Backwards compatibility.** Omitting `transitionError` preserves
## every v0.9.2 diagnostic byte-for-byte. The pragma is purely
## additive.

import ../src/typestates

type
  ResourceData = object
    handle: int

  Idle = distinct ResourceData
  Active = distinct ResourceData
  Released = distinct ResourceData

typestate Resource:
  consumeOnTransition = false
  strictTransitions = false
  states Idle, Active, Released
  initial:
    Idle
  terminal:
    Released
  transitions:
    Idle -> Active
    Active -> Released

proc `=destroy`(a: var Active)
    {.destructorTransition: Active -> Released,
      transitionError:
        "Active Resource must transition to Released before destruction".} =
  ## `{.destructorTransition.}` two-arg form combined with a sibling
  ## `transitionError:` pragma. The destination is pinned (Released)
  ## and the custom error string is held in reserve for the case where
  ## the destructor declaration drifts away from a valid terminal
  ## transition during future refactoring.
  echo "  [resource] destructor releasing handle ", a.ResourceData.handle

proc acquire(r: Idle): Active
    {.transition, transitionError:
      "Resource must be Idle before acquire; check the lifecycle diagram".} =
  ## `{.transition.}` with a pinned error message. The string is
  ## harvested at pragma-expansion time and surfaces only when the
  ## transition declaration is invalid (e.g., the source/destination
  ## edge is not declared in the typestate). For this valid edge the
  ## custom message is held in reserve.
  Active(r)

proc release(r: Active): Released {.transition.} =
  ## Plain `{.transition.}` without `transitionError`. The built-in
  ## diagnostic would surface if this edge were invalid.
  Released(r.ResourceData)

proc run() =
  let r = Idle(ResourceData(handle: 42))
  let a = acquire(r)
  let done = release(a)
  echo "  [run] released handle=", done.ResourceData.handle

verifyTypestates()

when isMainModule:
  echo "=== Transition-Error Demo (v0.9.3) ==="
  echo "1. Happy path (custom error message held in reserve):"
  run()
  echo "=== Done ==="
