## Compile-time registry for typestate definitions.
##
## This module provides a global compile-time registry that stores all
## declared typestates. The registry enables:
##
## - Looking up typestates by name
## - Finding which typestate a state type belongs to
## - Extending typestates across modules
##
## The registry is used by the `{.transition.}` pragma to validate that
## transitions are allowed.
##
## **Internal module** - most users won't interact with this directly.

import std/[tables, macros, options]
import types

export tables # Needed for `in` operator on Table

var typestateRegistry* {.compileTime.}: Table[string, TypestateGraph]
  ## Global compile-time storage for all registered typestates.
  ##
  ## Maps typestate names (e.g., "File") to their graph definitions.
  ## This variable is populated by the `typestate` macro and queried
  ## by the `{.transition.}` pragma.

proc validateBridgeDestinations(graph: TypestateGraph) {.compileTime.} =
  ## Validate that all bridge destinations reference existing states.
  ##
  ## For each bridge declared in the graph, checks that:
  ## 1. The destination typestate exists in the registry
  ## 2. The destination state exists in that typestate
  ##
  ## :param graph: The typestate graph to validate
  ## :raises: Compile-time error if any bridge destination is invalid
  for bridge in graph.bridges:
    let destTypestateBase = extractBaseName(bridge.toTypestate)
    if destTypestateBase notin typestateRegistry:
      # Destination typestate not registered yet - this is OK, will be validated
      # when the transition proc is implemented via the {.transition.} pragma
      continue

    let destGraph = typestateRegistry[destTypestateBase]
    let destStateBase = extractBaseName(bridge.toState)

    # Check if the destination state exists in the destination typestate
    var foundState = false
    for stateKey, state in destGraph.states:
      if state.name == destStateBase:
        foundState = true
        break

    if not foundState:
      var validStates: seq[string] = @[]
      for stateKey, state in destGraph.states:
        validStates.add state.name
      error(
        "Bridge destination state '" & bridge.toState & "' does not exist in typestate '" &
          bridge.toTypestate & "'. Valid states: " & $validStates
      )

template registerTypestate*(graph: TypestateGraph) =
  ## Register a typestate graph in the compile-time registry.
  ##
  ## Each typestate can only be defined once. Attempting to register
  ## a typestate with the same name twice results in a compile error.
  ##
  ## Example:
  ##
  ## ```nim
  ## typestate File:
  ##   states Closed, Open
  ##   transitions:
  ##     Closed -> Open
  ##     Open -> Closed
  ## ```
  ##
  ## :param graph: The typestate graph to register
  if graph.name in typestateRegistry:
    error(
      "Typestate '" & graph.name & "' is already defined. " &
        "Each typestate can only be declared once."
    )

  typestateRegistry[graph.name] = graph

  # Validate bridge destinations after registration
  validateBridgeDestinations(graph)

template hasTypestate*(name: string): bool =
  ## Check if a typestate with the given name exists in the registry.
  ##
  ## :param name: The typestate name to look up
  ## :returns: `true` if registered, `false` otherwise
  name in typestateRegistry

template getTypestate*(name: string): TypestateGraph =
  ## Retrieve a typestate graph by name.
  ##
  ## :param name: The typestate name to look up
  ## :returns: The `TypestateGraph` for the typestate
  ## :raises: Compile-time error if not found
  block:
    if name notin typestateRegistry:
      error("Unknown typestate: " & name)
    typestateRegistry[name]

proc findTypestateForState*(stateName: string): Option[TypestateGraph] {.compileTime.} =
  ## Find which typestate a given state belongs to.
  ##
  ## Searches all registered typestates to find one containing the
  ## specified state. Used by the `{.transition.}` pragma to determine
  ## which typestate graph to validate against.
  ##
  ## Lookups use base names to support generic types:
  ## - `findTypestateForState("Empty")` finds `typestate Container` with `Empty[T]`
  ##
  ## Example:
  ##
  ## ```nim
  ## # If File typestate has states Closed, Open:
  ## findTypestateForState("Closed")  # some(FileGraph)
  ## findTypestateForState("Unknown") # none
  ##
  ## # If Container typestate has states Empty[T], Full[T]:
  ## findTypestateForState("Empty")   # some(ContainerGraph)
  ## ```
  ##
  ## :param stateName: The state type name (base name, e.g., "Closed", "Empty")
  ## :returns: `some(graph)` if found, `none` if state is not in any typestate
  let searchBase = extractBaseName(stateName)
  for name, graph in typestateRegistry:
    for stateKey, state in graph.states:
      if state.name == searchBase:
        return some(graph)
  return none(TypestateGraph)

type AttachmentInfo* = object
  ## Information about a §3.7 typestate-attachment registration (v0.9.0).
  ##
  ## When a user-defined object type is bound to a typestate via a
  ## `{.<typestateName>: <initialState>.}` pragma (the typestate-attachment
  ## pragma), this record captures the binding so destructorTransition's
  ## source resolution (§3.1.1, path (b)) can recover the initial state.
  ##
  ## :var typestateName: Name of the typestate the type is attached to
  ## :var initialState: The initial state for instances of the attached type
  ## :var declaredAt: Source location of the attachment pragma
  typestateName*: string
  initialState*: string
  declaredAt*: LineInfo

var typestateAttachments* {.compileTime.}: Table[string, AttachmentInfo]
  ## Maps attached object type names (base names) to their attachment
  ## record. Populated by the per-typestate attachment-pragma macro emitted
  ## by the `typestate` macro (see `codegen.generateAttachmentMarker` and
  ## `pragmas.attachTypestateCore`).

proc findAttachmentForType*(
    typeName: string
): Option[AttachmentInfo] {.compileTime.} =
  ## Look up the §3.7 attachment record for an object type by base name.
  ##
  ## Used by `destructorTransitionCore` (pragmas.nim) as the fallback
  ## source-resolution path when `findTypestateForState` does not match
  ## (i.e., the destructor's `var T` parameter is not itself a registered
  ## typestate state, but is an object type bound to a typestate via the
  ## attachment pragma).
  ##
  ## :param typeName: Object type name (extractBaseName already applied)
  ## :returns: `some(info)` if registered, `none` otherwise
  let key = extractBaseName(typeName)
  if key in typestateAttachments:
    return some(typestateAttachments[key])
  return none(AttachmentInfo)

proc addAttachment*(
    typeName: string, info: AttachmentInfo
) {.compileTime.} =
  ## Register a typestate-attachment binding for an object type (§3.7).
  ##
  ## Stores under the base name of `typeName` (generic params stripped).
  ## Callers are responsible for emitting TA-004 if the key is already
  ## present; this proc unconditionally overwrites, so duplicate detection
  ## must happen BEFORE the call.
  ##
  ## :param typeName: Attached object type name (will be base-extracted)
  ## :param info: The attachment record to store
  let key = extractBaseName(typeName)
  typestateAttachments[key] = info

type BranchTypeInfo* = object
  ## Information about a user-defined branch type.
  ##
  ## When a branching transition like `Created -> (Approved | Declined) as ProcessResult`
  ## is declared, the user provides the type name. This object captures the
  ## relationship between the branch type name and the original transition.
  sourceState*: string ## The source state name ("Created")
  destinations*: seq[string] ## The destination states (["Approved", "Declined"])

proc findBranchTypeInfo*(typeName: string): Option[BranchTypeInfo] {.compileTime.} =
  ## Check if a type name is a user-defined branch type.
  ##
  ## Branch types are named by the user via `as TypeName` syntax in
  ## branching transitions.
  ##
  ## This function searches all registered typestates for branching
  ## transitions that declare the given branch type name.
  ##
  ## Example:
  ##
  ## ```nim
  ## # If typestate has: Created -> (Approved | Declined) as ProcessResult
  ## findBranchTypeInfo("ProcessResult")
  ## # Returns: some(BranchTypeInfo(sourceState: "Created",
  ## #                              destinations: @["Approved", "Declined"]))
  ##
  ## findBranchTypeInfo("NotABranch")
  ## # Returns: none(BranchTypeInfo)
  ## ```
  ##
  ## :param typeName: The type name to check
  ## :returns: `some(info)` if it's a branch type, `none` otherwise
  let typeBase = extractBaseName(typeName)

  # Search for a branching transition with this user-provided type name
  for name, graph in typestateRegistry:
    for trans in graph.transitions:
      if trans.toStates.len > 1 and not trans.isWildcard:
        # Compare base names (handles generic branch types like EmptyCheck[N])
        if extractBaseName(trans.branchTypeName) == typeBase:
          return some(
            BranchTypeInfo(
              sourceState: extractBaseName(trans.fromState),
              destinations: trans.toStates,
            )
          )

  return none(BranchTypeInfo)
