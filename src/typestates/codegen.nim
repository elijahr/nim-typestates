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

proc generateStateDollar*(graph: TypestateGraph): NimNode =
  ## Generate `$` overload for each leaf state type and the state enum.
  ##
  ## For each state, emits a proc returning the bare state name:
  ##
  ## ```nim
  ## proc `$`*(s: Closed): string = "Closed"
  ## proc `$`*[T](s: Empty[T]): string = "Empty"
  ## ```
  ##
  ## Also emits a `$` over the generated state enum that strips the `fs` prefix:
  ##
  ## ```nim
  ## proc `$`*(s: FileState): string =
  ##   case s
  ##   of fsClosed: "Closed"
  ##   of fsOpen: "Open"
  ## ```
  ##
  ## :param graph: The typestate graph
  ## :returns: AST for `$` overloads (one per state + one over the enum)
  result = newStmtList()

  let dollarIdent = nnkAccQuoted.newTree(ident("$"))
  let stringIdent = ident("string")
  let enumName = ident(graph.name & "State")

  # Per-state $ overload. Mirrors the signature of `generateStateProcs` so the
  # last-read consume rules are identical.
  for state in graph.states.values:
    let stateType = state.typeName.copyNimTree
    let nameLit = newLit(state.name)
    let docComment = newCommentStmtNode(
      "String representation for state '" & state.name & "'.\n" &
        "Returns the bare state name (no fs prefix)."
    )
    let procDef = nnkProcDef.newTree(
      nnkPostfix.newTree(ident("*"), dollarIdent.copyNimTree),
      newEmptyNode(),
      buildGenericParams(graph.typeParams),
      nnkFormalParams.newTree(
        stringIdent, nnkIdentDefs.newTree(ident("s"), stateType, newEmptyNode())
      ),
      newEmptyNode(),
      newEmptyNode(),
      nnkStmtList.newTree(docComment, nameLit),
    )
    result.add procDef

  # Enum $ overload (strips fs prefix)
  var caseStmt = nnkCaseStmt.newTree(ident("s"))
  for state in graph.states.values:
    let fieldName = ident("fs" & state.name)
    caseStmt.add nnkOfBranch.newTree(fieldName, newLit(state.name))
  let enumDocComment = newCommentStmtNode(
    "String representation of " & graph.name & "State enum.\n" &
      "Strips the fs prefix for human-friendly output."
  )
  let enumProcDef = nnkProcDef.newTree(
    nnkPostfix.newTree(ident("*"), dollarIdent.copyNimTree),
    newEmptyNode(),
    newEmptyNode(), # enum $ is not generic
    nnkFormalParams.newTree(
      stringIdent, nnkIdentDefs.newTree(ident("s"), enumName, newEmptyNode())
    ),
    newEmptyNode(),
    newEmptyNode(),
    nnkStmtList.newTree(enumDocComment, caseStmt),
  )
  result.add enumProcDef

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

proc generateBranchDollar*(graph: TypestateGraph): NimNode =
  ## Generate `$` overload for each branching union type.
  ##
  ## For a branching transition `Created -> A | B | C as Result`, emits:
  ##
  ## ```nim
  ## proc `$`*(r: Result): string =
  ##   case r.kind
  ##   of pA: "A"
  ##   of pB: "B"
  ##   of pC: "C"
  ## ```
  ##
  ## For generic typestates the union type includes the typestate's type
  ## parameters so the proc binds correctly under generic instantiation.
  ##
  ## :param graph: The typestate graph
  ## :returns: AST for `$` overloads over branching union types (one per union)
  result = newStmtList()

  let dollarIdent = nnkAccQuoted.newTree(ident("$"))
  let stringIdent = ident("string")

  for t in getBranchingTransitions(graph):
    if t.branchTypeName.len == 0:
      continue # Only branching transitions with `as ResultName` produce a union type.
    # For generic typestates we want the AST node (e.g. `Result[T]`) so the
    # generated `$` proc binds correctly under generic instantiation. For
    # non-generic typestates the bare ident is sufficient.
    let unionTypeNode =
      if graph.typeParams.len > 0 and t.branchTypeNode != nil:
        t.branchTypeNode.copyNimTree
      else:
        ident(extractBaseName(t.branchTypeName))
    let prefix = branchEnumPrefix(extractBaseName(t.branchTypeName))
    let kindAccess = newDotExpr(ident("r"), ident("kind"))
    var caseStmt = nnkCaseStmt.newTree(kindAccess)
    for destBase in t.toStates:
      let baseName = extractBaseName(destBase)
      let kindField = ident(prefix & baseName)
      caseStmt.add nnkOfBranch.newTree(kindField, newLit(baseName))
    let docComment = newCommentStmtNode(
      "String representation of branching union '" & t.branchTypeName &
        "'.\nReturns the active branch's bare state name."
    )
    let procDef = nnkProcDef.newTree(
      nnkPostfix.newTree(ident("*"), dollarIdent.copyNimTree),
      newEmptyNode(),
      buildGenericParams(graph.typeParams),
      nnkFormalParams.newTree(
        stringIdent, nnkIdentDefs.newTree(ident("r"), unionTypeNode, newEmptyNode())
      ),
      newEmptyNode(),
      newEmptyNode(),
      nnkStmtList.newTree(docComment, caseStmt),
    )
    result.add procDef

proc buildMatchCase*(
    value: NimNode, arms: NimNode, validNames: seq[string], kindSyms: seq[NimNode]
): NimNode =
  ## INTERNAL: this helper is exported for use by the generated `match` macro
  ## via `bindSym`. User code should not call it directly.
  ##
  ## Helper used by every generated `match` macro to rewrite an arms block
  ## into a `case value.kind` statement.
  ##
  ## - `value`: NimNode for the matched union value (passed to the macro).
  ## - `arms`: NimNode for the StmtList of `Call(StateIdent, bindIdent, body)` arms.
  ## - `validNames`: bare base names of the union's branches (e.g. @["Approved", "Declined"]).
  ## - `kindSyms`: pre-resolved sym nodes for each branch's kind-enum field, in the
  ##   same order as `validNames`. Resolved at the typestate-decl call site (where
  ##   the kind enum is in scope) so consumer modules that do not import the kind
  ##   enum directly can still expand `match` correctly.
  ##
  ## Errors at the user's call site for malformed arms or unknown-branch names.
  ## Exhaustiveness is enforced by Nim's case-statement checker once the
  ## resulting AST is sema-checked.
  doAssert validNames.len == kindSyms.len,
    "buildMatchCase: validNames and kindSyms must have the same length"
  result = newStmtList()
  var caseStmt = nnkCaseStmt.newTree(newDotExpr(value, ident("kind")))
  for clause in arms:
    if clause.kind != nnkCall or clause.len != 3:
      error(
        "match expects `StateName(bindName): body` per arm, got: " & clause.repr, clause
      )
    let stateIdent = clause[0]
    let bindIdent = clause[1]
    let clauseBody = clause[2]
    # Accept the node kinds Nim's sema produces for the arm head:
    #   - nnkIdent: untyped context (module-top-level call site).
    #   - nnkSym: sema has resolved the arm head to a concrete symbol, which
    #     happens when `match` is invoked from inside the body of a generic
    #     proc/template (sema runs on the body before the macro expands).
    #   - nnkOpenSymChoice / nnkClosedSymChoice: the arm head identifier is
    #     overloaded across imports; sema produces a symchoice node. All
    #     children of a symchoice share the same identifier name, so taking
    #     the first child's strVal is unambiguous.
    let stateName =
      case stateIdent.kind
      of nnkIdent, nnkSym:
        stateIdent.strVal
      of nnkOpenSymChoice, nnkClosedSymChoice:
        stateIdent[0].strVal
      else:
        error("match arm head must be a single state identifier", stateIdent)
    if bindIdent.kind != nnkIdent:
      error("match arm bind must be a single identifier", bindIdent)
    var matchedIdx = -1
    for i, n in validNames:
      if n == stateName:
        matchedIdx = i
        break
    if matchedIdx < 0:
      error(
        "unknown branch '" & stateName & "' is not part of this union; valid branches: " &
          $validNames,
        stateIdent,
      )
    # Use the pre-resolved kind-enum sym (bound at the typestate-decl site).
    # This sidesteps the bug where a bare `ident(prefix & stateName)` would fail
    # to resolve at the consumer's call site when the kind enum is not directly
    # imported there (e.g. `match` invoked from a generic proc body in a module
    # whose facade does not re-export the enum).
    let kindField = kindSyms[matchedIdx]
    let varFieldName = stateName.toLowerAscii()
    let extract =
      newLetStmt(bindIdent, newCall("move", newDotExpr(value, ident(varFieldName))))
    var rewritten = newStmtList(extract)
    if clauseBody.kind == nnkStmtList:
      for stmt in clauseBody:
        rewritten.add stmt
    else:
      rewritten.add clauseBody
    caseStmt.add nnkOfBranch.newTree(kindField, rewritten)
  result.add caseStmt

proc buildSingleTargetMatchCase*(
    value: NimNode, arms: NimNode, validStateName: string
): NimNode =
  ## INTERNAL: this helper is exported for use by the generated single-target
  ## `match` macro via `bindSym`. User code should not call it directly.
  ##
  ## Helper used by every generated single-target `match` macro to rewrite an
  ## arms block of the shape `StateName(bindName): body` into a hygienic
  ## `block:` statement that moves the matched value into the bound name and
  ## then runs the body.
  ##
  ## - `value`: NimNode for the matched state value (passed to the macro).
  ## - `arms`: NimNode for the StmtList of `Call(StateIdent, bindIdent, body)` arms.
  ## - `validStateName`: bare base name of the only valid state (e.g. "Approved").
  ##
  ## Two-path AST emit driven by `value.kind`:
  ##
  ## - L-value source (`nnkIdent`/`nnkSym`/`nnkDotExpr`/`nnkBracketExpr`):
  ##   ```nim
  ##   block:
  ##     let bind = move(value)
  ##     body
  ##   ```
  ##   `move()` accepts the l-value directly; no copy hook is invoked. The
  ##   l-value MUST be a `var` binding (e.g. `var a = ...; match a:`) because
  ##   `system.move` requires a `var T` parameter. A `let`-bound source emits
  ##   the standard "expression is immutable, not 'var'" error at the user's
  ##   call site.
  ##
  ## - R-value source (call expressions, etc.):
  ##   ```nim
  ##   block:
  ##     var valTmp`gensym = value
  ##     let bind = move(valTmp`gensym)
  ##     body
  ##   ```
  ##   Materializing the rvalue into a `var` goes through `=sink`
  ##   (sink-on-construction), not `=copy`, so the `{.error.}` copy hook on
  ##   distinct state types is never reached. The temp is required because
  ##   `move()` demands a `var` binding.
  ##
  ## The `block:` wrapper provides hygiene so adjacent matches with the same
  ## bind name don't collide.
  ##
  ## Errors at the user's call site for malformed arms or a state-name
  ## mismatch.
  if arms.kind != nnkStmtList:
    error("single-target match expects a StmtList of arms", arms)

  # Filter empty nodes (nnkEmpty separators) and comment statements
  # (so users can document arms inline without tripping the multi-arm check).
  var armNodes: seq[NimNode] = @[]
  for n in arms:
    if n.kind notin {nnkEmpty, nnkCommentStmt}:
      armNodes.add n

  if armNodes.len == 0:
    error(
      "single-target match expects `" & validStateName & "(bindName): body`, got: " &
        arms.repr,
      arms,
    )
  if armNodes.len > 1:
    error(
      "single-target match accepts exactly one arm; got " & $armNodes.len, armNodes[1]
    )

  let clause = armNodes[0]
  if clause.kind != nnkCall or clause.len != 3:
    error(
      "single-target match expects `" & validStateName & "(bindName): body`, got: " &
        clause.repr,
      clause,
    )

  let stateIdent = clause[0]
  let bindIdent = clause[1]
  let clauseBody = clause[2]

  # Same node-kind acceptance set as buildMatchCase (codegen.nim:735-742):
  # nnkIdent (untyped), nnkSym (sema-resolved in generic body), and
  # nnkOpenSymChoice / nnkClosedSymChoice (overloaded).
  let stateName =
    case stateIdent.kind
    of nnkIdent, nnkSym:
      stateIdent.strVal
    of nnkOpenSymChoice, nnkClosedSymChoice:
      stateIdent[0].strVal
    else:
      error("match arm head must be a single state identifier", stateIdent)
      "" # unreachable; satisfies type checker

  if stateName != validStateName:
    error(
      "unknown state '" & stateName & "' for single-target match; expected '" &
        validStateName & "'",
      stateIdent,
    )

  if bindIdent.kind != nnkIdent:
    error("match arm bind must be a single identifier", bindIdent)

  # Two-path emit based on whether `value` is an l-value or r-value.
  # L-value sources can be moved directly (assuming the user bound them with
  # `var`); r-value sources need a `var` temp for sink-on-construction.
  # nnkPar covers `match (myVar):` — a parenthesized l-value should still
  # take the direct-move path, not the var-temp r-value path.
  const lvalueKinds = {nnkIdent, nnkSym, nnkDotExpr, nnkBracketExpr, nnkPar}
  var rewritten = newStmtList()
  if value.kind in lvalueKinds:
    # Path 1: l-value source — move directly, no temp.
    let extract = newLetStmt(bindIdent, newCall("move", value))
    rewritten.add extract
  else:
    # Path 2: r-value source (call expr etc.) — materialize into a `var`
    # temp so `move()` has a mutable binding, then move. `var tmp = value`
    # goes through `=sink`, not `=copy`, so the distinct copy-error hook
    # is never hit.
    let valTmp = genSym(nskVar, "matchValTmp")
    let tmpDef =
      nnkVarSection.newTree(nnkIdentDefs.newTree(valTmp, newEmptyNode(), value))
    let extract = newLetStmt(bindIdent, newCall("move", valTmp))
    rewritten.add tmpDef
    rewritten.add extract
  if clauseBody.kind == nnkStmtList:
    for stmt in clauseBody:
      rewritten.add stmt
  else:
    rewritten.add clauseBody
  result = nnkBlockStmt.newTree(newEmptyNode(), rewritten)

proc generateBranchMatch*(graph: TypestateGraph): NimNode =
  ## Generate a `match` macro for each branching union type.
  ##
  ## For a transition `Created -> (Approved | Declined) as ProcessResult`,
  ## emits a macro with this signature:
  ##
  ## ```nim
  ## macro match*(value: ProcessResult; body: untyped): untyped =
  ##   ## Pattern-match on a branching union; rewrites into a `case` over the
  ##   ## kind discriminator.
  ## ```
  ##
  ## Call-site syntax (the body is a list of `Call(StateIdent, bindIdent, body)`):
  ##
  ## ```nim
  ## match r:
  ##   Approved(a): doSomething(a)
  ##   Declined(d): handleDecline(d)
  ## ```
  ##
  ## Rewritten to:
  ##
  ## ```nim
  ## case value.kind
  ## of pApproved:
  ##   let a = move(value.approved)
  ##   doSomething(a)
  ## of pDeclined:
  ##   let d = move(value.declined)
  ##   handleDecline(d)
  ## ```
  ##
  ## Exhaustiveness is provided by Nim's `case` statement: missing branches
  ## produce "not all cases are covered" at compile time. Branches naming a
  ## state outside the union produce an explicit "unknown branch" error.
  ##
  ## Multiple branching unions in the same module each get their own `match`
  ## macro; Nim disambiguates via the typed first parameter (verified by the
  ## F4.A0 probe).
  ##
  ## :param graph: The typestate graph
  ## :returns: AST for one `match` macro per branching union
  result = newStmtList()

  for t in getBranchingTransitions(graph):
    if t.branchTypeName.len == 0:
      continue
    let prefix = branchEnumPrefix(extractBaseName(t.branchTypeName))
    # Bake the list of valid base-state names so the generated macro can
    # report unknown-branch errors at the user's call site.
    var validNamesNode = nnkPrefix.newTree(ident("@"), nnkBracket.newTree())
    for dest in t.toStates:
      validNamesNode[1].add newLit(extractBaseName(dest))
    # The union type. For generic typestates we use the AST node so the macro
    # signature binds correctly under instantiation; for non-generic, the bare
    # ident is sufficient.
    let unionTypeNode =
      if graph.typeParams.len > 0 and t.branchTypeNode != nil:
        t.branchTypeNode.copyNimTree
      else:
        ident(extractBaseName(t.branchTypeName))

    # The body of the generated `match` macro is a single call to the public
    # helper `buildMatchCase`. This keeps all the NimNode-walking and
    # macros-stdlib symbol resolution inside the typestates package, so the
    # call site (which only imports `typestates`) does not need
    # `import std/macros`. We still need `bindSym` for `buildMatchCase` so the
    # generated macro can find it without the user having to re-import.
    let helperSym = bindSym("buildMatchCase")
    # Resolve `bindSym` itself as a typestates-scope sym so the generated macro
    # body can call it without the user importing std/macros. The generated
    # macro is compiled in the user's module, so any plain `bindSym(...)` call
    # in its body would be unresolved unless the user also imports std/macros.
    let bindSymRef = bindSym("bindSym")
    # Build the parallel kindSyms seq node. Each element is a `bindSym("mFoo")`
    # call. `bindSym` resolves identifiers in the SCOPE OF THE MACRO BEING
    # COMPILED — i.e. the user's module where the kind enum was just declared
    # by the same `typestate` macro. This decouples expansion from the
    # consumer's call-site scope, fixing the regression where consumer modules
    # that did not directly import the kind enum failed with
    # "undeclared identifier: 'mXxx'" when expanding `match` inside a generic
    # proc body.
    var kindSymsNode = nnkPrefix.newTree(ident("@"), nnkBracket.newTree())
    for dest in t.toStates:
      let fieldName = prefix & extractBaseName(dest)
      kindSymsNode[1].add nnkCall.newTree(bindSymRef, newLit(fieldName))
    let matchDoc = newCommentStmtNode(
      "Pattern-match on a branching union; rewrites into a `case` over " &
        "the kind discriminator.\n" &
        "The value being matched must be a `var` binding. Branch fields " &
        "are extracted with `move()`, which requires a mutable binding. " &
        "Syntax is `StateName(bind):`, not `of StateName as bind:`."
    )
    let macroBody = newStmtList(
      matchDoc,
      nnkAsgn.newTree(
        ident("result"),
        nnkCall.newTree(
          helperSym, ident("value"), ident("arms"), validNamesNode, kindSymsNode
        ),
      ),
    )

    let matchMacro = nnkMacroDef.newTree(
      nnkPostfix.newTree(ident("*"), ident("match")),
      newEmptyNode(),
      buildGenericParams(graph.typeParams),
      nnkFormalParams.newTree(
        ident("untyped"),
        nnkIdentDefs.newTree(ident("value"), unionTypeNode, newEmptyNode()),
        nnkIdentDefs.newTree(ident("arms"), ident("untyped"), newEmptyNode()),
      ),
      newEmptyNode(),
      newEmptyNode(),
      macroBody,
    )

    result.add matchMacro

proc generateSingleTargetMatch*(graph: TypestateGraph): NimNode =
  ## Generate a `match` macro for each state, supporting single-target match.
  ##
  ## For every state in the graph, emits a macro with this signature:
  ##
  ## ```nim
  ## macro match*(value: <StateType>; arms: untyped): untyped =
  ##   ## Single-target pattern match; rewrites to `block: let bind = move(value); body`.
  ## ```
  ##
  ## Call-site syntax (exactly one arm naming the state):
  ##
  ## ```nim
  ## match a:
  ##   Approved(x):
  ##     useApproved(x)
  ## ```
  ##
  ## Rewritten to:
  ##
  ## ```nim
  ## block:
  ##   let x = move(a)
  ##   useApproved(x)
  ## ```
  ##
  ## R-value sources (e.g. call expressions) are first materialized into a
  ## gensym'd `let` so `move()` has an l-value. Sink-on-construction avoids
  ## the `=copy` error hook on distinct state types.
  ##
  ## The per-state `match` overloads coexist with the per-branching-union
  ## `match` overloads emitted by `generateBranchMatch`; Nim disambiguates
  ## by the typed first parameter. The parser-side collision validator
  ## prevents same-name overload duplication between a state and a branch
  ## wrapper type.
  ##
  ## :param graph: The typestate graph
  ## :returns: AST for one `match` macro per state
  result = newStmtList()

  for state in graph.states.values:
    if state.typeName == nil or state.name.len == 0:
      continue

    let stateType = state.typeName.copyNimTree
    let stateNameLit = newLit(state.name)

    # The body of the generated `match` macro is a single call to the public
    # helper `buildSingleTargetMatchCase`, mirroring `generateBranchMatch`.
    # Using `bindSym` keeps the helper resolution inside the typestates
    # package so user modules don't need `import std/macros`.
    let helperSym = bindSym("buildSingleTargetMatchCase")
    let matchDoc = newCommentStmtNode(
      "Single-target pattern match on state '" & state.name &
        "'; rewrites to `block: let bind = move(value); body`.\n" & "Syntax is `" &
        state.name & "(bind):`, with exactly one arm."
    )
    let macroBody = newStmtList(
      matchDoc,
      nnkAsgn.newTree(
        ident("result"),
        nnkCall.newTree(helperSym, ident("value"), ident("arms"), stateNameLit),
      ),
    )

    let matchMacro = nnkMacroDef.newTree(
      nnkPostfix.newTree(ident("*"), ident("match")),
      newEmptyNode(),
      buildGenericParams(graph.typeParams),
      nnkFormalParams.newTree(
        ident("untyped"),
        nnkIdentDefs.newTree(ident("value"), stateType, newEmptyNode()),
        nnkIdentDefs.newTree(ident("arms"), ident("untyped"), newEmptyNode()),
      ),
      newEmptyNode(),
      newEmptyNode(),
      macroBody,
    )

    result.add matchMacro

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
  ## 8. Branch `$` overloads
  ## 9. Per-branching-union `match` macros
  ## 10. Per-state single-target `match` macros
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
  result.add generateStateDollar(graph)
  result.add generateCopyHooks(graph)
  result.add generateBranchTypes(graph)
  result.add generateBranchConstructors(graph)
  result.add generateBranchOperators(graph)
  result.add generateBranchDollar(graph)
  result.add generateBranchMatch(graph)
  result.add generateSingleTargetMatch(graph)
