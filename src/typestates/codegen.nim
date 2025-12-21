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

proc buildGenericParams*(typeParams: seq[NimNode]): NimNode =
  ## Build a generic params node for proc/type definitions.
  ##
  ## For `@[T]`, generates: `[T]`
  ## For `@[K, V]`, generates: `[K, V]`
  ## For `@[N: static int]`, generates: `[N: static int]`
  ## For `@[T: SomeInteger]`, generates: `[T: SomeInteger]`
  ## For `@[]`, returns empty node (non-generic)
  ##
  ## :param typeParams: Sequence of type parameter nodes
  ## :returns: nnkGenericParams node or newEmptyNode()
  if typeParams.len == 0:
    return newEmptyNode()
  result = nnkGenericParams.newTree()
  for p in typeParams:
    if p.kind == nnkExprColonExpr:
      # Constrained generic: N: static int or T: SomeInteger
      # ExprColonExpr[0] = name (N or T)
      # ExprColonExpr[1] = constraint (static int or SomeInteger)
      result.add nnkIdentDefs.newTree(
        p[0].copyNimTree, # name
        p[1].copyNimTree, # constraint
        newEmptyNode(), # default value
      )
    else:
      # Simple generic: T
      result.add nnkIdentDefs.newTree(p.copyNimTree, newEmptyNode(), newEmptyNode())

proc extractTypeParams*(node: NimNode): seq[NimNode] =
  ## Extract type parameters from a type node.
  ##
  ## For `FillResult[T]`, returns `@[T]`
  ## For `Map[K, V]`, returns `@[K, V]`
  ## For `Simple`, returns `@[]`
  ##
  ## :param node: A type AST node (ident or bracket expr)
  ## :returns: Sequence of type parameter nodes
  result = @[]
  if node.kind == nnkBracketExpr:
    for i in 1 ..< node.len:
      result.add node[i].copyNimTree

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
      nnkPostfix.newTree(ident("*"), enumName), newEmptyNode(), enumFields
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
  ## type ContainerStates*[T] = Empty[T] | Full[T]
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
      ident("|"), states[0].typeName.copyNimTree, states[1].typeName.copyNimTree
    )
    for i in 2 ..< states.len:
      unionType =
        nnkInfix.newTree(ident("|"), unionType, states[i].typeName.copyNimTree)

  result = nnkTypeSection.newTree(
    nnkTypeDef.newTree(
      nnkPostfix.newTree(ident("*"), unionName),
      buildGenericParams(graph.typeParams),
      unionType,
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
      buildGenericParams(graph.typeParams),
      nnkFormalParams.newTree(
        enumName, nnkIdentDefs.newTree(ident("f"), stateType, newEmptyNode())
      ),
      newEmptyNode(),
      newEmptyNode(),
      nnkStmtList.newTree(docComment, fieldName),
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
  ## `Created -> (Approved | Declined)`
  ##
  ## :param graph: The typestate graph to query
  ## :returns: Sequence of branching transitions
  result = @[]
  for t in graph.transitions:
    if t.toStates.len > 1 and not t.isWildcard:
      result.add t

proc branchEnumPrefix(typeName: string): string =
  ## Generate a short prefix for branch enum fields.
  ##
  ## Uses first letter of type name (lowercase) to create prefixes:
  ## - "ProcessResult" -> "p"
  ## - "OpenResult" -> "o"
  ## - "ReviewDecision" -> "r"
  result = typeName[0].toLowerAscii().`$`

proc generateBranchTypes*(graph: TypestateGraph): NimNode =
  ## Generate variant types for branching transitions.
  ##
  ## For a transition like `Created -> (Approved | Declined) as ProcessResult`,
  ## generates:
  ##
  ## ```nim
  ## type
  ##   ProcessResultKind* = enum pApproved, pDeclined
  ##   ProcessResult* = object
  ##     case kind*: ProcessResultKind
  ##     of pApproved: approved*: Approved
  ##     of pDeclined: declined*: Declined
  ## ```
  ##
  ## For generic types like `Empty[T] -> Full[T] | Error[T] as FillResult[T]`:
  ##
  ## ```nim
  ## type
  ##   FillResultKind* = enum fFull, fError
  ##   FillResult*[T] = object
  ##     case kind*: FillResultKind
  ##     of fFull: full*: Full[T]
  ##     of fError: error*: Error[T]
  ## ```
  ##
  ## The type name comes from the `as TypeName` syntax in the DSL.
  ## Enum prefixes are derived from the first letter of the type name.
  ##
  ## :param graph: The typestate graph to generate from
  ## :returns: AST for all branch type definitions
  result = newStmtList()

  let branchingTransitions = graph.getBranchingTransitions()
  if branchingTransitions.len == 0:
    return

  for t in branchingTransitions:
    let branchTypeName = t.branchTypeName
    let branchTypeNode = t.branchTypeNode
    let branchBaseName = extractBaseName(branchTypeName)
    # Use typestate's type params (with constraints) instead of extracting from branch type
    let branchTypeParams = graph.typeParams
    let kindTypeName = branchBaseName & "Kind"
    let enumPrefix = branchEnumPrefix(branchBaseName)

    # Generate enum: CreatedBranchKind = enum cbApproved, cbDeclined, ...
    var enumFields = nnkEnumTy.newTree(newEmptyNode())
    for dest in t.toStates:
      let destBase = extractBaseName(dest)
      let fieldName = ident(enumPrefix & destBase)
      enumFields.add fieldName

    let enumDef = nnkTypeDef.newTree(
      nnkPostfix.newTree(ident("*"), ident(kindTypeName)), newEmptyNode(), enumFields
    )

    # Generate object variant: CreatedBranch = object case kind: ...
    var recCase = nnkRecCase.newTree(
      nnkIdentDefs.newTree(
        nnkPostfix.newTree(ident("*"), ident("kind")),
        ident(kindTypeName),
        newEmptyNode(),
      )
    )

    for dest in t.toStates:
      let destBase = extractBaseName(dest)
      let fieldName = ident(enumPrefix & destBase)
      # Field name is lowercase version of state name
      let varFieldName = destBase.toLowerAscii()

      # Get the full type from the graph's states (lookup by full name)
      var destType: NimNode
      if dest in graph.states:
        destType = graph.states[dest].typeName.copyNimTree
      else:
        destType = ident(destBase)

      let branch = nnkOfBranch.newTree(
        fieldName,
        nnkRecList.newTree(
          nnkIdentDefs.newTree(
            nnkPostfix.newTree(ident("*"), ident(varFieldName)),
            destType,
            newEmptyNode(),
          )
        ),
      )
      recCase.add branch

    # Use base name for type definition, generic params go in second slot
    let objectDef = nnkTypeDef.newTree(
      nnkPostfix.newTree(ident("*"), ident(branchBaseName)),
      buildGenericParams(branchTypeParams),
      nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), nnkRecList.newTree(recCase)),
    )

    # Add both to a type section
    result.add nnkTypeSection.newTree(enumDef, objectDef)

proc generateBranchConstructors*(graph: TypestateGraph): NimNode =
  ## Generate constructor procs for branch types.
  ##
  ## For `Created -> (Approved | Declined) as ProcessResult`, generates:
  ##
  ## ```nim
  ## proc toProcessResult*(s: Approved): ProcessResult =
  ##   ProcessResult(kind: pApproved, approved: s)
  ##
  ## proc toProcessResult*(s: Declined): ProcessResult =
  ##   ProcessResult(kind: pDeclined, declined: s)
  ## ```
  ##
  ## For generic types:
  ##
  ## ```nim
  ## proc toFillResult*[T](s: Full[T]): FillResult[T] =
  ##   FillResult[T](kind: fFull, full: s)
  ## ```
  ##
  ## :param graph: The typestate graph to generate from
  ## :returns: AST for all constructor proc definitions
  result = newStmtList()

  let branchingTransitions = graph.getBranchingTransitions()
  if branchingTransitions.len == 0:
    return

  for t in branchingTransitions:
    let branchTypeName = t.branchTypeName
    let branchTypeNode = t.branchTypeNode
    let branchBaseName = extractBaseName(branchTypeName)
    # Use typestate's type params (with constraints) instead of extracting from branch type
    let branchTypeParams = graph.typeParams
    let procName = "to" & branchBaseName
    let enumPrefix = branchEnumPrefix(branchBaseName)

    for dest in t.toStates:
      let destBase = extractBaseName(dest)
      let kindField = ident(enumPrefix & destBase)
      let varFieldName = destBase.toLowerAscii()

      # Get the full type from the graph's states (lookup by full name)
      var destType: NimNode
      if dest in graph.states:
        destType = graph.states[dest].typeName.copyNimTree
      else:
        destType = ident(destBase)

      # Build: ProcessResult(kind: pApproved, approved: s)
      let constructorCall = nnkObjConstr.newTree(
        branchTypeNode.copyNimTree,
        nnkExprColonExpr.newTree(ident("kind"), kindField),
        nnkExprColonExpr.newTree(ident(varFieldName), ident("s")),
      )

      let procDef = nnkProcDef.newTree(
        nnkPostfix.newTree(ident("*"), ident(procName)),
        newEmptyNode(),
        buildGenericParams(branchTypeParams),
        nnkFormalParams.newTree(
          branchTypeNode.copyNimTree,
          nnkIdentDefs.newTree(
            ident("s"),
            nnkCommand.newTree(ident("sink"), destType), # Use sink to consume the state
            newEmptyNode(),
          ),
        ),
        newEmptyNode(),
        newEmptyNode(),
        nnkStmtList.newTree(constructorCall),
      )

      result.add procDef

proc generateCopyHooks*(graph: TypestateGraph): NimNode =
  ## Generate `=copy` error hooks to prevent state copying.
  ##
  ## When `consumeOnTransition = true`, generates:
  ##
  ## ```nim
  ## proc `=copy`*(dest: var Closed, src: Closed) {.error: "State 'Closed' cannot be copied. Transitions consume the input state.".}
  ## ```
  ##
  ## This enforces linear/affine typing - each state value can only be used once.
  ##
  ## :param graph: The typestate graph to generate from
  ## :returns: AST for all copy hook definitions
  result = newStmtList()

  if not graph.consumeOnTransition:
    return

  for state in graph.states.values:
    let stateType = state.typeName.copyNimTree
    let errorMsg =
      "State '" & state.name & "' cannot be copied. Transitions consume the input state."

    # proc `=copy`*(dest: var StateType, src: StateType) {.error: "...".}
    let hookDef = nnkProcDef.newTree(
      nnkPostfix.newTree(ident("*"), nnkAccQuoted.newTree(ident("=copy"))),
      newEmptyNode(),
      buildGenericParams(graph.typeParams),
      nnkFormalParams.newTree(
        newEmptyNode(), # void return
        nnkIdentDefs.newTree(ident("dest"), nnkVarTy.newTree(stateType), newEmptyNode()),
        nnkIdentDefs.newTree(ident("src"), stateType, newEmptyNode()),
      ),
      nnkPragma.newTree(
        nnkExprColonExpr.newTree(ident("error"), newStrLitNode(errorMsg))
      ),
      newEmptyNode(),
      newEmptyNode(),
    )

    result.add hookDef

proc hasStaticGenericParam*(graph: TypestateGraph): bool =
  ## Check if typestate has any static generic parameters (e.g., `N: static int`).
  ##
  ## These are vulnerable to a codegen bug in Nim < 2.2.8 when combined
  ## with `=copy` hooks on distinct types. Affects ARC, ORC, AtomicARC,
  ## and any memory manager using hooks.
  ##
  ## :param graph: The typestate graph to check
  ## :returns: `true` if any type parameter uses `static`
  for param in graph.typeParams:
    if param.kind == nnkExprColonExpr:
      let constraint = param[1]
      # Check for "static X" pattern (nnkCommand with "static" as first child)
      if constraint.kind == nnkCommand and constraint.len >= 1:
        if constraint[0].kind == nnkIdent and constraint[0].strVal == "static":
          return true
  return false

proc hasHookCodegenBugConditions*(graph: TypestateGraph): bool =
  ## Check if this typestate has conditions that trigger a codegen bug in Nim < 2.2.8.
  ##
  ## The bug occurs when all these conditions are met:
  ## 1. Distinct types (implicit - all typestate states are distinct)
  ## 2. Plain object (not inheriting from RootObj)
  ## 3. Generic with `static` parameter (e.g., `N: static int`)
  ## 4. Lifecycle hooks are generated (`consumeOnTransition = true`)
  ##
  ## Note: Condition 1 is always true for typestates. Condition 2 is checked
  ## via the `inheritsFromRootObj` flag (we can't detect inheritance at macro time).
  ##
  ## Affects ARC, ORC, AtomicARC, and any memory manager using hooks.
  ## Fixed in Nim commit 099ee1ce4a308024781f6f39ddfcb876f4c3629c (>= 2.2.8).
  ## See: https://github.com/nim-lang/Nim/issues/25341
  ##
  ## :param graph: The typestate graph to check
  ## :returns: `true` if vulnerable conditions are present
  not graph.inheritsFromRootObj and graph.consumeOnTransition and
    hasStaticGenericParam(graph)

proc generateBranchOperators*(graph: TypestateGraph): NimNode =
  ## Generate `->` operator templates for branch types.
  ##
  ## The `->` operator provides syntactic sugar for branch construction.
  ## It takes the branch type on the left and the state value on the right:
  ##
  ## ```nim
  ## # Usage (for: Created -> Approved | Declined as ProcessResult):
  ## ProcessResult -> Approved(c.Payment)
  ##
  ## # Equivalent to:
  ## toProcessResult(Approved(c.Payment))
  ## ```
  ##
  ## For generic types:
  ##
  ## ```nim
  ## FillResult[int] -> Full[int](container)
  ## ```
  ##
  ## Generated templates:
  ##
  ## ```nim
  ## template `->`*(T: typedesc[ProcessResult], s: Approved): ProcessResult =
  ##   toProcessResult(s)
  ##
  ## template `->`*[T](T: typedesc[FillResult[T]], s: Full[T]): FillResult[T] =
  ##   toFillResult(s)
  ## ```
  ##
  ## The `typedesc` parameter disambiguates when the same state appears
  ## in multiple branch types.
  ##
  ## :param graph: The typestate graph to generate from
  ## :returns: AST for all operator template definitions
  result = newStmtList()

  let branchingTransitions = graph.getBranchingTransitions()
  if branchingTransitions.len == 0:
    return

  for t in branchingTransitions:
    let branchTypeName = t.branchTypeName
    let branchTypeNode = t.branchTypeNode
    let branchBaseName = extractBaseName(branchTypeName)
    # Use typestate's type params (with constraints) instead of extracting from branch type
    let branchTypeParams = graph.typeParams
    let procName = "to" & branchBaseName

    for dest in t.toStates:
      let destBase = extractBaseName(dest)

      # Get the full type from the graph's states (lookup by full name)
      var destType: NimNode
      if dest in graph.states:
        destType = graph.states[dest].typeName.copyNimTree
      else:
        destType = ident(destBase)

      # Build: toProcessResult(s)
      let callExpr = nnkCall.newTree(ident(procName), ident("s"))

      # template `->`*(T: typedesc[ProcessResult], s: sink Approved): ProcessResult =
      #   toProcessResult(s)
      let templateDef = nnkTemplateDef.newTree(
        nnkPostfix.newTree(ident("*"), nnkAccQuoted.newTree(ident("->"))),
        newEmptyNode(),
        buildGenericParams(branchTypeParams),
        nnkFormalParams.newTree(
          branchTypeNode.copyNimTree,
          nnkIdentDefs.newTree(
            ident("_"),
            nnkBracketExpr.newTree(ident("typedesc"), branchTypeNode.copyNimTree),
            newEmptyNode(),
          ),
          nnkIdentDefs.newTree(
            ident("s"),
            nnkCommand.newTree(ident("sink"), destType), # Use sink to consume the state
            newEmptyNode(),
          ),
        ),
        newEmptyNode(),
        newEmptyNode(),
        nnkStmtList.newTree(callExpr),
      )

      result.add templateDef

proc generateAll*(graph: TypestateGraph): NimNode =
  ## Generate all helper types and procs for a typestate.
  ##
  ## This is the main entry point called by the `typestate` macro.
  ## It generates:
  ##
  ## 1. State enum (`FileState`)
  ## 2. Union type (`FileStates` or `ContainerStates[T]`)
  ## 3. State procs (`state()` for each state)
  ## 4. Copy hooks (`=copy` error hooks when consumeOnTransition = true)
  ## 5. Branch types for branching transitions (user-named via `as TypeName`)
  ## 6. Branch constructors (`toTypeName`)
  ## 7. Branch operators (`->`)
  ##
  ## For generic typestates like `Container[T]`, all generated types
  ## and procs include proper type parameters.
  ##
  ## :param graph: The typestate graph to generate from
  ## :returns: AST containing all generated definitions
  result = newStmtList()

  result.add generateStateEnum(graph)
  result.add generateUnionType(graph)
  result.add generateStateProcs(graph)
  result.add generateCopyHooks(graph)
  result.add generateBranchTypes(graph)
  result.add generateBranchConstructors(graph)
  result.add generateBranchOperators(graph)
