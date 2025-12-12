## Test: Module qualifiers are metadata, not enforced
##
## This test documents that module qualifiers in bridge syntax are:
## 1. Stored and used for visualization/documentation
## 2. NOT validated against actual module names
## 3. NOT used for state lookup (which uses base names only)
##
## This design allows flexibility in how bridges are documented while
## maintaining correctness through base name matching.

import ../src/typestates

type
  DestinationType = object
    value: int

  DestinationState = distinct DestinationType

typestate DestinationType:
  consumeOnTransition = false
  states DestinationState

type
  SourceType = object
    data: int

  SourceState = distinct SourceType

typestate SourceType:
  consumeOnTransition = false
  states SourceState
  bridges:
    # Using an arbitrary module qualifier that doesn't match any real module
    # This is valid because module qualifiers are metadata for documentation
    SourceState -> arbitrary.module.path.DestinationType.DestinationState

# Bridge implementation works regardless of module qualifier
proc bridgeToDest(s: SourceState): DestinationState {.transition.} =
  DestinationState(DestinationType(value: SourceType(s).data * 2))

# Test that bridge works despite arbitrary module qualifier
block test_module_qualifier_is_metadata:
  let source = SourceState(SourceType(data: 21))
  let dest = bridgeToDest(source)
  doAssert DestinationType(dest).value == 42
  echo "Bridge works with arbitrary module qualifier (metadata only)"

# Test with no module qualifier
type
  LogType = object
    text: string

  LogEntry = distinct LogType

typestate LogType:
  consumeOnTransition = false
  states LogEntry

type
  ProcessType = object
    info: string

  ProcessReady = distinct ProcessType

typestate ProcessType:
  consumeOnTransition = false
  states ProcessReady
  bridges:
    # No module qualifier - just Typestate.State
    ProcessReady -> LogType.LogEntry

proc bridgeToLog(s: ProcessReady): LogEntry {.transition.} =
  LogEntry(LogType(text: ProcessType(s).info & "!"))

block test_no_module_qualifier:
  let source = ProcessReady(ProcessType(info: "test"))
  let dest = bridgeToLog(source)
  doAssert LogType(dest).text == "test!"
  echo "Bridge works without module qualifier"

echo "Module qualifier metadata tests passed"
