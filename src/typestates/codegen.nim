## Code generation for typestate helper types.
##
## This module generates the helper types and procs that make typestates
## easier to use at runtime:
##
## - **State enum**: `FileState = enum fsClosed, fsOpen, ...`
## - **Union type**: `FileStates = Closed | Open | ...`
## - **State procs**: `proc state(f: Closed): FileState`
## - **Branch types**: `CreatedBranch` variant for `Created -> Approved | Declined`
## - **Branch constructors**: `toCreatedBranch(s: Approved): CreatedBranch`
##
## These are generated automatically by the `typestate` macro.

import std/[macros, sequtils, strutils, tables]
import types

proc generateStateEnum*(graph: TypestateGraph): NimNode =
  ## Generate a runtime enum representing all states.
  ##
  ## For a typestate named `File` with states `Closed`, `Open`, `Errored`,
  ## generates:
  ##
  ## ```nim
  ## type FileState* = enum
  ##   fsClosed, fsOpen, fsErrored
  ## ```
  ##
  ## For generic typestates like `Container[T]` with states `Empty[T]`, `Full[T]`:
  ##
  ## ```nim
  ## type ContainerState* = enum
  ##   fsEmpty, fsFull
  ## ```
  ##
  ## The enum values use base names (without type params) prefixed with `fs`.
  ##
  ## :param graph: The typestate graph to generate from
  ## :returns: AST for the enum type definition
  let enumName = ident(graph.name & "State")

  var enumFields = nnkEnumTy.newTree(newEmptyNode())
  for state in graph.states.values:
    # Use base name: "Empty" from "Empty[T]"
    let fieldName = ident("fs" & state.name)
    enumFields.add fieldName

  result = nnkTypeSection.newTree(
    nnkTypeDef.newTree(
      nnkPostfix.newTree(ident("*"), enumName),
      newEmptyNode(),
      enumFields
    )
  )

proc generateUnionType*(graph: TypestateGraph): NimNode =
  ## Generate a type alias for "any state" using Nim's union types.
  ##
  ## For a typestate named `File` with states `Closed`, `Open`, `Errored`,
  ## generates:
  ##
  ## ```nim
  ## type FileStates* = Closed | Open | Errored
  ## ```
  ##
  ## For generic typestates like `Container[T]`:
  ##
  ## ```nim
  ## type ContainerStates* = Empty[T] | Full[T]
  ## ```
  ##
  ## This union type is useful for procs that can accept any state.
  ##
  ## :param graph: The typestate graph to generate from
  ## :returns: AST for the union type definition
  let unionName = ident(graph.name & "States")

  var states = toSeq(graph.states.values)

  if states.len == 0:
    error("Typestate has no states")

  var unionType: NimNode
  if states.len == 1:
    # Use the stored AST node directly
    unionType = states[0].typeName.copyNimTree
  else:
    # Build: State1 | State2 | State3 using stored AST nodes
    unionType = nnkInfix.newTree(
      ident("|"),
      states[0].typeName.copyNimTree,
      states[1].typeName.copyNimTree
    )
    for i in 2 ..< states.len:
      unionType = nnkInfix.newTree(
        ident("|"),
        unionType,
        states[i].typeName.copyNimTree
      )

  result = nnkTypeSection.newTree(
    nnkTypeDef.newTree(
      nnkPostfix.newTree(ident("*"), unionName),
      newEmptyNode(),
      unionType
    )
  )

proc generateStateProcs*(graph: TypestateGraph): NimNode =
  ## Generate `state()` procs for runtime state inspection.
  ##
  ## For each state, generates a proc that returns the enum value:
  ##
  ## ```nim
  ## proc state*(f: Closed): FileState = fsClosed
  ## proc state*(f: Open): FileState = fsOpen
  ## ```
  ##
  ## For generic types:
  ##
  ## ```nim
  ## proc state*[T](f: Empty[T]): ContainerState = fsEmpty
  ## proc state*[T](f: Full[T]): ContainerState = fsFull
  ## ```
  ##
  ## :param graph: The typestate graph to generate from
  ## :returns: AST for all state() proc definitions
  result = newStmtList()

  let enumName = ident(graph.name & "State")

  for state in graph.states.values:
    # Use base name for enum field: "fsEmpty" from "Empty[T]"
    let fieldName = ident("fs" & state.name)
    # Use stored AST node for parameter type
    let stateType = state.typeName.copyNimTree

    # Build proc with doc comment
    let docComment = newCommentStmtNode(
      "Runtime state inspection for " & state.name & ".\n" &
      "Returns the enum value for pattern matching in case expressions."
    )
    let procDef = nnkProcDef.newTree(
      nnkPostfix.newTree(ident("*"), ident("state")),
      newEmptyNode(),
      newEmptyNode(),
      nnkFormalParams.newTree(
        enumName,
        nnkIdentDefs.newTree(
          ident("f"),
          stateType,
          newEmptyNode()
        )
      ),
      newEmptyNode(),
      newEmptyNode(),
      nnkStmtList.newTree(docComment, fieldName)
    )

    result.add procDef

proc hasGenericStates*(graph: TypestateGraph): bool =
  ## Check if any states use generic type parameters.
  for state in graph.states.values:
    if state.typeName.kind == nnkBracketExpr:
      return true
  return false

proc getBranchingTransitions*(graph: TypestateGraph): seq[Transition] =
  ## Get all transitions that have multiple destinations (branching).
  ##
  ## A branching transition is one where `toStates.len > 1`, like:
  ## `Created -> Approved | Declined`
  ##
  ## :param graph: The typestate graph to query
  ## :returns: Sequence of branching transitions
  result = @[]
  for t in graph.transitions:
    if t.toStates.len > 1 and not t.isWildcard:
      result.add t

proc branchEnumPrefix(fromState: string): string =
  ## Generate a short prefix for branch enum fields.
  ##
  ## Uses first letter of source state + "b" to create unique prefixes:
  ## - "Created" -> "cb"
  ## - "Review" -> "rb"
  ## - "Pending" -> "pb"
  result = fromState[0].toLowerAscii() & "b"

proc generateBranchTypes*(graph: TypestateGraph): NimNode =
  ## Generate variant types for branching transitions.
  ##
  ## For a transition like `Created -> Approved | Declined | Review`,
  ## generates:
  ##
  ## ```nim
  ## type
  ##   CreatedBranchKind* = enum cbApproved, cbDeclined, cbReview
  ##   CreatedBranch* = object
  ##     case kind*: CreatedBranchKind
  ##     of cbApproved: approved*: Approved
  ##     of cbDeclined: declined*: Declined
  ##     of cbReview: review*: Review
  ## ```
  ##
  ## For `Review -> Approved | Declined`:
  ##
  ## ```nim
  ## type
  ##   ReviewBranchKind* = enum rbApproved, rbDeclined
  ##   ...
  ## ```
  ##
  ## Enum prefixes are derived from source state (cb=Created, rb=Review)
  ## to avoid naming conflicts.
  ##
  ## :param graph: The typestate graph to generate from
  ## :returns: AST for all branch type definitions
  result = newStmtList()

  let branchingTransitions = graph.getBranchingTransitions()
  if branchingTransitions.len == 0:
    return

  for t in branchingTransitions:
    let fromState = extractBaseName(t.fromState)
    let branchTypeName = fromState & "Branch"
    let kindTypeName = fromState & "BranchKind"
    let enumPrefix = branchEnumPrefix(fromState)

    # Generate enum: CreatedBranchKind = enum cbApproved, cbDeclined, ...
    var enumFields = nnkEnumTy.newTree(newEmptyNode())
    for dest in t.toStates:
      let destBase = extractBaseName(dest)
      let fieldName = ident(enumPrefix & destBase)
      enumFields.add fieldName

    let enumDef = nnkTypeDef.newTree(
      nnkPostfix.newTree(ident("*"), ident(kindTypeName)),
      newEmptyNode(),
      enumFields
    )

    # Generate object variant: CreatedBranch = object case kind: ...
    var recCase = nnkRecCase.newTree(
      nnkIdentDefs.newTree(
        nnkPostfix.newTree(ident("*"), ident("kind")),
        ident(kindTypeName),
        newEmptyNode()
      )
    )

    for dest in t.toStates:
      let destBase = extractBaseName(dest)
      let fieldName = ident(enumPrefix & destBase)
      # Field name is lowercase version of state name
      let varFieldName = destBase.toLowerAscii()

      # Get the full type from the graph's states
      var destType: NimNode
      if destBase in graph.states:
        destType = graph.states[destBase].typeName.copyNimTree
      else:
        destType = ident(destBase)

      let branch = nnkOfBranch.newTree(
        fieldName,
        nnkRecList.newTree(
          nnkIdentDefs.newTree(
            nnkPostfix.newTree(ident("*"), ident(varFieldName)),
            destType,
            newEmptyNode()
          )
        )
      )
      recCase.add branch

    let objectDef = nnkTypeDef.newTree(
      nnkPostfix.newTree(ident("*"), ident(branchTypeName)),
      newEmptyNode(),
      nnkObjectTy.newTree(
        newEmptyNode(),
        newEmptyNode(),
        nnkRecList.newTree(recCase)
      )
    )

    # Add both to a type section
    result.add nnkTypeSection.newTree(enumDef, objectDef)

proc generateBranchConstructors*(graph: TypestateGraph): NimNode =
  ## Generate constructor procs for branch types.
  ##
  ## For each branching transition, generates `toXBranch` procs:
  ##
  ## ```nim
  ## proc toCreatedBranch*(s: Approved): CreatedBranch =
  ##   CreatedBranch(kind: cbApproved, approved: s)
  ##
  ## proc toCreatedBranch*(s: Declined): CreatedBranch =
  ##   CreatedBranch(kind: cbDeclined, declined: s)
  ## ```
  ##
  ## :param graph: The typestate graph to generate from
  ## :returns: AST for all constructor proc definitions
  result = newStmtList()

  let branchingTransitions = graph.getBranchingTransitions()
  if branchingTransitions.len == 0:
    return

  for t in branchingTransitions:
    let fromState = extractBaseName(t.fromState)
    let branchTypeName = fromState & "Branch"
    let procName = "to" & branchTypeName
    let enumPrefix = branchEnumPrefix(fromState)

    for dest in t.toStates:
      let destBase = extractBaseName(dest)
      let kindField = ident(enumPrefix & destBase)
      let varFieldName = destBase.toLowerAscii()

      # Get the full type from the graph's states
      var destType: NimNode
      if destBase in graph.states:
        destType = graph.states[destBase].typeName.copyNimTree
      else:
        destType = ident(destBase)

      # Build: CreatedBranch(kind: cbApproved, approved: s)
      let constructorCall = nnkObjConstr.newTree(
        ident(branchTypeName),
        nnkExprColonExpr.newTree(ident("kind"), kindField),
        nnkExprColonExpr.newTree(ident(varFieldName), ident("s"))
      )

      let procDef = nnkProcDef.newTree(
        nnkPostfix.newTree(ident("*"), ident(procName)),
        newEmptyNode(),
        newEmptyNode(),
        nnkFormalParams.newTree(
          ident(branchTypeName),
          nnkIdentDefs.newTree(
            ident("s"),
            destType,
            newEmptyNode()
          )
        ),
        newEmptyNode(),
        newEmptyNode(),
        nnkStmtList.newTree(constructorCall)
      )

      result.add procDef

proc generateAll*(graph: TypestateGraph): NimNode =
  ## Generate all helper types and procs for a typestate.
  ##
  ## This is the main entry point called by the `typestate` macro.
  ## It generates:
  ##
  ## 1. State enum (`FileState`)
  ## 2. Union type (`FileStates`)
  ## 3. State procs (`state()` for each state)
  ## 4. Branch types for branching transitions (`CreatedBranch`, etc.)
  ## 5. Branch constructors (`toCreatedBranch`)
  ##
  ## **Note:** For generic typestates like `Container[T]`, helper generation
  ## is currently skipped because the generated types would need to be
  ## parameterized. The core typestate validation still works.
  ##
  ## :param graph: The typestate graph to generate from
  ## :returns: AST containing all generated definitions
  result = newStmtList()

  # Skip helper generation for generic typestates (for now)
  # The type parameters aren't in scope for the generated code
  if graph.hasGenericStates:
    return

  result.add generateStateEnum(graph)
  result.add generateUnionType(graph)
  result.add generateStateProcs(graph)
  result.add generateBranchTypes(graph)
  result.add generateBranchConstructors(graph)
