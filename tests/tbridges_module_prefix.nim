## Test module.Typestate.State syntax

import ../src/typestates
import ./bridges_module_dest

type
  SourceType = object
    data: int

  SourceA = distinct SourceType
  SourceB = distinct SourceType

typestate SourceType:
  consumeOnTransition = false
  states SourceA, SourceB
  transitions:
    SourceA -> SourceB
  bridges:
    # This is the NEW syntax - module prefix
    SourceB -> bridges_module_dest.DestTypestate.DestStateA

proc toBridgeDest(s: SourceB): DestStateA {.transition.} =
  DestStateA(DestTypestate(id: s.SourceType.data))

block test_module_prefix_bridge:
  let source = SourceB(SourceType(data: 99))
  let dest = toBridgeDest(source)
  doAssert dest.DestTypestate.id == 99
  echo "Module prefix bridge syntax works"

echo "All module prefix bridge tests passed"
