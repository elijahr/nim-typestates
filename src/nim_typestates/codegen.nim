import std/[macros, sequtils, tables]
import types

proc generateStateEnum*(graph: TypestateGraph): NimNode =
  ## Generate: type FileState = enum fsClosed, fsOpen, ...
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
  ## Generate: type FileStates* = Closed | Open | Errored
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
  ## Generate: proc state(f: Closed): FileState = fsClosed
  result = newStmtList()

  let enumName = ident(graph.name & "State")

  for stateName in graph.states.keys:
    let stateIdent = ident(stateName)
    let fieldName = ident("fs" & stateName)

    let procDef = quote do:
      proc state*(f: `stateIdent`): `enumName` = `fieldName`

    result.add procDef

proc generateAll*(graph: TypestateGraph): NimNode =
  ## Generate all helper types and procs
  result = newStmtList()
  result.add generateStateEnum(graph)
  result.add generateUnionType(graph)
  result.add generateStateProcs(graph)
