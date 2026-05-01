## F5: Generic typestates are deferred to v0.6 — decoys MUST NOT be
## emitted for them. Calling a generic transition with the wrong source
## state must still fail compilation, but with Nim's GENERIC type-mismatch
## diagnostic, not the F5 tailored message.
##
## If decoy emission ever expands to cover generic typestates, this test
## breaks because the error message changes shape.
# expects: "type mismatch"
import ../../../src/typestates

type
  Container[T] = object
    value: T

  Empty[T] = distinct Container[T]
  Full[T] = distinct Container[T]

typestate Container[T]:
  consumeOnTransition = false
  strictTransitions = false
  states Empty[T], Full[T]
  transitions:
    Empty[T] -> Full[T]

proc fill(e: sink Empty[int], v: int): Full[int] {.transition.} =
  Full[int](Container[int](value: v))

verifyTypestates()

# Wrong source: pass Full[int] into fill(), which expects Empty[int].
# A decoy would fire the F5 tailored "Cannot call 'fill' on a value
# in state 'Full'…" — but generic typestates are skipped, so the
# generic Nim diagnostic must surface.
let f = Full[int](Container[int](value: 7))
discard f.fill(1)
