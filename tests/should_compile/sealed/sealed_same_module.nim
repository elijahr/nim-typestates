## Test: Sealed typestate with all transitions in same file works
import ../../../src/typestates

type
  Document = object
    content: string

  Draft = distinct Document
  Published = distinct Document
  Archived = distinct Document

typestate Document:
  consumeOnTransition = false # Opt out for existing tests
  # All typestates are sealed (no extension allowed)
  strictTransitions = false
  states Draft, Published, Archived
  transitions:
    Draft -> Published
    Published -> Archived

proc publish(d: Draft): Published {.transition.} =
  Published(d.Document)

proc archive(d: Published): Archived {.transition.} =
  Archived(d.Document)

let draft = Draft(Document(content: "Hello"))
let published = draft.publish()
let archived = published.archive()
echo "sealed_same_module test passed"
