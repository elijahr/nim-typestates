## Code generation for typestate helper types.
##
## This module generates the helper types and procs that make typestates
## easier to use at runtime:
##
## - **State enum**: `FileState = enum fsClosed, fsOpen, ...`
## - **Union type**: `FileStates = Closed | Open | ...`
## - **State procs**: `proc state(f: Closed): FileState`
##
## These are generated automatically by the `typestate` macro.

import std/[macros, sequtils, tables]
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
  ## The enum values are prefixed with `fs` to avoid naming conflicts.
  ##
  ## - `graph`: The typestate graph to generate from
  ## - Returns: AST for the enum type definition
  let enumName = ident(graph.name & "State")

  var enumFields = nnkEnumTy.newTree(newEmptyNode())
  for stateName in graph.states.keys:
    # Convert "Closed" to "fsClosed"
    let fieldName = ident("fs" & stateName)
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
  ## This union type is useful for procs that can accept any state,
  ## such as a generic `close` proc.
  ##
  ## - `graph`: The typestate graph to generate from
  ## - Returns: AST for the union type definition
  ##
  ## Example usage:
  ##
  ## ```nim
  ## proc forceClose[S: FileStates](f: S): Closed =
  ##   # Works with any state
  ##   result = Closed(f.File)
  ## ```
  let unionName = ident(graph.name & "States")

  var stateNames = toSeq(graph.states.keys)

  if stateNames.len == 0:
    error("Typestate has no states")

  var unionType: NimNode
  if stateNames.len == 1:
    unionType = ident(stateNames[0])
  else:
    # Build: State1 | State2 | State3
    unionType = nnkInfix.newTree(
      ident("|"),
      ident(stateNames[0]),
      ident(stateNames[1])
    )
    for i in 2 ..< stateNames.len:
      unionType = nnkInfix.newTree(
        ident("|"),
        unionType,
        ident(stateNames[i])
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
  ## proc state*(f: Errored): FileState = fsErrored
  ## ```
  ##
  ## This enables runtime state checking when needed:
  ##
  ## ```nim
  ## case someState.state
  ## of fsClosed: echo "File is closed"
  ## of fsOpen: echo "File is open"
  ## of fsErrored: echo "File has error"
  ## ```
  ##
  ## - `graph`: The typestate graph to generate from
  ## - Returns: AST for all state() proc definitions
  result = newStmtList()

  let enumName = ident(graph.name & "State")

  for stateName in graph.states.keys:
    let stateIdent = ident(stateName)
    let fieldName = ident("fs" & stateName)

    # Build proc with doc comment manually since quote doesn't support ##
    let docComment = newCommentStmtNode(
      "Runtime state inspection for " & stateName & ".\n" &
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
          stateIdent,
          newEmptyNode()
        )
      ),
      newEmptyNode(),
      newEmptyNode(),
      nnkStmtList.newTree(docComment, fieldName)
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
  ##
  ## - `graph`: The typestate graph to generate from
  ## - Returns: AST containing all generated definitions
  result = newStmtList()
  result.add generateStateEnum(graph)
  result.add generateUnionType(graph)
  result.add generateStateProcs(graph)
