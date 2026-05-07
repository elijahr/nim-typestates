## Two adjacent single-target matches in the same proc, both binding the
## same identifier (`x`). Verifies that the `block:` wrapper provides
## hygiene so the two binds do not collide.
import ../../../src/typestates

type
  Tag = object
    s: string
  Raw = distinct Tag
  Cooked = distinct Tag

typestate Tag:
  states Raw, Cooked
  transitions:
    Raw -> Cooked

proc cook(r: sink Raw): Cooked {.transition.} =
  Cooked(Tag(r))

var c1 = Raw(Tag(s: "a")).cook()
var c2 = Raw(Tag(s: "b")).cook()

var labels: seq[string] = @[]
match c1:
  Cooked(x):
    labels.add Tag(x).s
match c2:
  Cooked(x):     # same bind name as previous match — must not collide
    labels.add Tag(x).s

doAssert labels == @["a", "b"]
echo "match_single_target_two_sequential test passed"
