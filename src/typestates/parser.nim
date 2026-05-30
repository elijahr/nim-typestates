## Parser for the typestate DSL.
##
## This module transforms the AST from a `typestate` macro invocation into
## a `TypestateGraph` structure. It handles parsing of:
##
## - State declarations (`states Closed, Open, Errored`)
## - Transition declarations (`Closed -> Open | Errored`)
## - Wildcard transitions (`* -> Closed`)
##
## The parser operates at compile-time within macro context.
##
## **Internal module** - most users won't interact with this directly.

import std/[macros, tables, strutils, sets]
import types
import reachability

proc extractBaseName(node: NimNode): string =
  ## Extract the base type name from any type expression.
  ##
  ## - `Closed` -> "Closed"
  ## - `Container[T]` -> "Container"
  ## - `ref Closed` -> "Closed"
  ## - `ptr Container[T]` -> "Container"
  ## - `mymodule.State` -> "State"
  case node.kind
  of nnkIdent:
    result = node.strVal
  of nnkSym:
    result = node.strVal
  of nnkBracketExpr:
    # Generic: Container[T] -> extract "Container"
    result = extractBaseName(node[0])
  of nnkRefTy, nnkPtrTy:
    # ref/ptr: extract from inner type
    result = extractBaseName(node[0])
  of nnkDotExpr:
    # Qualified: mymodule.State -> extract "State"
    result = extractBaseName(node[1])
  of nnkPostfix:
    # Exported: State* -> extract "State"
    result = extractBaseName(node[1])
  else:
    result = node.repr.split("[")[0].split(".")[^1].strip(chars = {'*', ' '})

proc parseStates*(graph: var TypestateGraph, node: NimNode) =
  ## Parse a states declaration and add states to the graph.
  ##
  ## Accepts multiple syntax forms:
  ##
  ## - Inline: `states Closed, Open, Errored`
  ## - Multiline block:
  ##   ```
  ##   states:
  ##     Closed
  ##     Open
  ##     Errored
  ##   ```
  ## - Multiline with commas:
  ##   ```
  ##   states:
  ##     Closed,
  ##     Open,
  ##     Errored
  ##   ```
  ##
  ## States can be any valid Nim type expression:
  ##
  ## - Simple identifiers: `Closed`, `Open`
  ## - Generic types: `Container[T]`, `Map[K, V]`
  ## - Ref types: `ref Closed`
  ## - Qualified names: `mymodule.State`
  ##
  ## Example AST inputs:
  ##
  ## ```
  ## # Simple: states Closed, Open
  ## Command
  ##   Ident "states"
  ##   Ident "Closed"
  ##   Ident "Open"
  ##
  ## # Generic: states Empty[T], Full[T]
  ## Command
  ##   Ident "states"
  ##   BracketExpr
  ##     Ident "Empty"
  ##     Ident "T"
  ##   BracketExpr
  ##     Ident "Full"
  ##     Ident "T"
  ##
  ## # Multiline: states:
  ## #             Closed
  ## #             Open
  ## Call
  ##   Ident "states"
  ##   StmtList
  ##     Ident "Closed"
  ##     Ident "Open"
  ## ```
  ##
  ## :param graph: The typestate graph to populate
  ## :param node: AST node of the states declaration
  ## :raises: Compile-time error if syntax is invalid
  if node.kind notin {nnkCall, nnkCommand}:
    error("Expected call or command for states", node)

  # First child is "states", rest are state type expressions or StmtList
  for i in 1 ..< node.len:
    let child = node[i]

    if child.kind == nnkStmtList:
      # Multiline block: each child is a state
      for stateNode in child:
        if stateNode.kind == nnkEmpty:
          continue
        # Handle trailing commas: strip from repr if present
        let baseName = extractBaseName(stateNode)
        var fullRepr = stateNode.repr.strip(chars = {',', ' ', '\n'})
        graph.states[fullRepr] =
          State(name: baseName, fullRepr: fullRepr, typeName: stateNode)
    else:
      # Inline: each child is a state
      let baseName = extractBaseName(child)
      let fullRepr = child.repr
      graph.states[fullRepr] =
        State(name: baseName, fullRepr: fullRepr, typeName: child)

proc collectBranchTargets(node: NimNode): seq[string] =
  ## Recursively collect all target states from a branching expression.
  ##
  ## Handles the `|` operator for branching transitions like `Open | Errored`.
  ## Also handles parenthesized groups like `(Open | Errored)` for clarity.
  ## States can be any valid type expression (simple, generic, ref, etc.).
  ##
  ## Examples:
  ##
  ## - `Open` -> `@["Open"]`
  ## - `Open | Errored` -> `@["Open", "Errored"]`
  ## - `(Open | Errored)` -> `@["Open", "Errored"]`
  ## - `Full[T] | Error[T]` -> `@["Full[T]", "Error[T]"]`
  ## - `A | B | C` -> `@["A", "B", "C"]`
  ##
  ## :param node: AST node representing the target(s)
  ## :returns: Sequence of state repr strings
  case node.kind
  of nnkIdent, nnkBracketExpr, nnkRefTy, nnkPtrTy, nnkDotExpr:
    # Any valid type expression - use its repr
    result = @[node.repr]
  of nnkInfix:
    if node[0].strVal == "|":
      result = collectBranchTargets(node[1]) & collectBranchTargets(node[2])
    else:
      error("Expected '|' in branching transition", node)
  of nnkPar:
    # Parenthesized expression like (A | B) - unwrap and recurse
    if node.len == 1:
      result = collectBranchTargets(node[0])
    else:
      error("Expected single expression in parentheses", node)
  else:
    # Fallback: try to use repr for any other node type
    result = @[node.repr]

proc parseTransition*(node: NimNode): Transition =
  ## Parse a single transition declaration.
  ##
  ## Supports three forms:
  ##
  ## - **Simple**: `Closed -> Open`
  ## - **Branching**: `Closed -> Open | Errored`
  ## - **Wildcard**: `* -> Closed`
  ##
  ## Example AST for `Closed -> Open | Errored`:
  ##
  ## ```
  ## Infix
  ##   Ident "->"
  ##   Ident "Closed"
  ##   Infix
  ##     Ident "|"
  ##     Ident "Open"
  ##     Ident "Errored"
  ## ```
  ##
  ## Example AST for `* -> Closed` (wildcard parsed as nested prefix):
  ##
  ## ```
  ## Prefix
  ##   Ident "*"
  ##   Prefix
  ##     Ident "->"
  ##     Ident "Closed"
  ## ```
  ##
  ## :param node: AST node of the transition expression
  ## :returns: A `Transition` object
  ## :raises: Compile-time error if syntax is invalid

  # Handle wildcard syntax: * -> X parses as nested Prefix nodes
  if node.kind == nnkPrefix and node[0].strVal == "*":
    let innerNode = node[1]
    if innerNode.kind == nnkPrefix and innerNode[0].strVal == "->":
      let toStates = collectBranchTargets(innerNode[1])
      return Transition(
        fromState: "*",
        toStates: toStates,
        isWildcard: true,
        declaredAt: node.lineInfoObj,
      )

  expectKind(node, nnkInfix)

  if node[0].strVal != "->":
    error("Expected '->' in transition", node[0])

  # Parse source state (can be any type expression)
  let sourceNode = node[1]
  var fromState: string
  var isWildcard = false

  case sourceNode.kind
  of nnkIdent:
    fromState = sourceNode.strVal
    if fromState == "*":
      isWildcard = true
  of nnkPrefix:
    # Handle * as prefix operator
    if sourceNode[0].strVal == "*":
      fromState = "*"
      isWildcard = true
    else:
      error("Unexpected prefix in transition source", sourceNode)
  of nnkBracketExpr, nnkRefTy, nnkPtrTy, nnkDotExpr:
    # Generic, ref, ptr, or qualified type - use repr
    fromState = sourceNode.repr
  else:
    # Fallback: try repr for any other valid type expression
    fromState = sourceNode.repr

  # Parse target state(s) and optional "as TypeName"
  # A -> B | C as ResultType parses as:
  #   Infix("->", A, Infix("as", Infix("|", B, C), ResultType))
  var targetsNode = node[2]
  var branchTypeName = ""

  var branchTypeNode: NimNode = nil

  if targetsNode.kind == nnkInfix and targetsNode[0].strVal == "as":
    # Extract the branch type name from RHS of "as"
    # Store both the string repr and the AST node (for generics like ResultType[T])
    branchTypeNode = targetsNode[2]
    branchTypeName = branchTypeNode.repr
    targetsNode = targetsNode[1]

  let toStates = collectBranchTargets(targetsNode)

  # Validate: branching transitions MUST have a type name
  if toStates.len > 1 and branchTypeName == "":
    error(
      "Branching transitions require a result type name. " & "Use: " & fromState & " -> " &
        toStates.join(" | ") & " as ResultTypeName",
      node,
    )

  # Validate: non-branching transitions should NOT have a type name
  if toStates.len == 1 and branchTypeName != "":
    error(
      "Non-branching transition should not have 'as " & branchTypeName & "'. " &
        "The 'as TypeName' syntax is only for branching transitions (A -> B | C).",
      node,
    )

  result = Transition(
    fromState: fromState,
    toStates: toStates,
    branchTypeName: branchTypeName,
    branchTypeNode: branchTypeNode,
    isWildcard: isWildcard,
    declaredAt: node.lineInfoObj,
  )

proc parseFlag(graph: var TypestateGraph, node: NimNode) =
  ## Parse a flag assignment like `strictTransitions = false`.
  ##
  ## :param graph: The typestate graph to update
  ## :param node: AST node of the assignment
  ## :raises: Compile-time error for unknown flags
  expectKind(node, nnkAsgn)

  let flagName = node[0].strVal
  let flagValue = node[1]

  # Handle both nnkIdent (direct) and nnkSym (from quote do)
  if flagValue.kind notin {nnkIdent, nnkSym}:
    error("Expected true or false for flag value", flagValue)
  let value = flagValue.strVal == "true"

  case flagName
  of "strictTransitions":
    graph.strictTransitions = value
  of "consumeOnTransition":
    graph.consumeOnTransition = value
  of "inheritsFromRootObj":
    graph.inheritsFromRootObj = value
  of "opaqueStates":
    graph.opaqueStates = value
  else:
    error(
      "Unknown flag: " & flagName &
        ". Valid flags: strictTransitions, consumeOnTransition, inheritsFromRootObj, opaqueStates",
      node,
    )

proc parseTransitionsBlock(graph: var TypestateGraph, node: NimNode) =
  ## Parse the transitions block and add all transitions to the graph.
  ##
  ## Example input:
  ##
  ## ```nim
  ## transitions:
  ##   Closed -> Open
  ##   Open -> Closed
  ## ```
  ##
  ## :param graph: The typestate graph to populate
  ## :param node: AST node of the transitions block
  ## :raises: Compile-time error if block is empty or malformed
  expectKind(node, nnkCall)

  # node[0] is "transitions", node[1] is the statement list
  if node.len < 2:
    error("transitions block is empty", node)

  let transBlock = node[1]
  expectKind(transBlock, nnkStmtList)

  for child in transBlock:
    let trans = parseTransition(child)
    graph.transitions.add(trans)

proc collectBridgeTargets(
    node: NimNode
): seq[tuple[module: string, typestate: string, state: string, fullRepr: string]] =
  ## Recursively collect all target typestates/states from a branching expression.
  ##
  ## Handles the `|` operator for branching bridges.
  ## Supports multiple syntax forms:
  ##
  ## - `Typestate.State` -> `[("", "Typestate", "State", "Typestate.State")]`
  ## - `module.Typestate.State` -> `[("module", "Typestate", "State", "module.Typestate.State")]`
  ## - `Typestate.State | Other.State` -> multiple tuples
  ##
  ## :param node: AST node representing the target(s)
  ## :returns: Sequence of (module, typestate, state, fullRepr) tuples
  case node.kind
  of nnkDotExpr:
    # Could be Typestate.State or module.Typestate.State (nested DotExpr)
    let fullRepr = node.repr

    if node[0].kind == nnkDotExpr:
      # Nested: module.Typestate.State
      # node[0] = module.Typestate (DotExpr)
      # node[1] = State (Ident)
      let moduleDot = node[0]
      let module = extractBaseName(moduleDot[0])
      let typestate = extractBaseName(moduleDot[1])
      let state = extractBaseName(node[1])
      result = @[(module, typestate, state, fullRepr)]
    else:
      # Simple: Typestate.State
      let typestate = extractBaseName(node[0])
      let state = extractBaseName(node[1])
      result = @[("", typestate, state, fullRepr)]
  of nnkInfix:
    if node[0].strVal == "|":
      result = collectBridgeTargets(node[1]) & collectBridgeTargets(node[2])
    else:
      error("Expected '|' in branching bridge", node)
  else:
    error(
      "Bridge destination must use dotted notation (Typestate.State or module.Typestate.State), got: " &
        node.repr,
      node,
    )

proc parseBridgesBlock*(graph: var TypestateGraph, node: NimNode) =
  ## Parse the bridges block and add all bridges to the graph.
  ##
  ## Example input:
  ##
  ## ```nim
  ## bridges:
  ##   Authenticated -> Session.Active
  ##   Failed -> ErrorLog.Entry
  ##   * -> Shutdown.Terminal
  ## ```
  ##
  ## :param graph: The typestate graph to populate
  ## :param node: AST node of the bridges block
  ## :raises: Compile-time error if block is malformed
  expectKind(node, nnkCall)

  # node[0] is "bridges", node[1] is the statement list
  if node.len < 2:
    error("bridges block is empty", node)

  let bridgesBlock = node[1]
  expectKind(bridgesBlock, nnkStmtList)

  for child in bridgesBlock:
    # Parse source state
    var fromState: string
    var targetsNode: NimNode

    # Handle wildcard: * -> X.Y parses as nested nnkPrefix
    if child.kind == nnkPrefix and child[0].strVal == "*":
      let innerNode = child[1]
      if innerNode.kind == nnkPrefix and innerNode[0].strVal == "->":
        fromState = "*"
        targetsNode = innerNode[1]
      else:
        error("Invalid wildcard bridge syntax", child)
    elif child.kind == nnkInfix and child[0].strVal == "->":
      let sourceNode = child[1]
      case sourceNode.kind
      of nnkIdent:
        fromState = sourceNode.strVal
      of nnkPrefix:
        if sourceNode[0].strVal == "*":
          fromState = "*"
        else:
          error("Unexpected prefix in bridge source", sourceNode)
      else:
        error("Expected identifier or wildcard in bridge source", sourceNode)

      targetsNode = child[2]
    else:
      error("Expected bridge declaration with '->'", child)

    # Collect all targets (handles branching with |)
    let targets = collectBridgeTargets(targetsNode)

    # Create a Bridge for each target
    for target in targets:
      let bridge = Bridge(
        fromState: fromState,
        toModule: target.module,
        toTypestate: target.typestate,
        toState: target.state,
        fullDestRepr: target.fullRepr,
        declaredAt: child.lineInfoObj,
      )
      graph.bridges.add bridge

proc parseStateList(node: NimNode): seq[string] =
  ## Parse a list of states from command/call syntax.
  ##
  ## Handles multiple syntax forms:
  ##
  ## - Inline: `initial: A, B, C`
  ## - Command: `initial A, B`
  ## - Multiline block:
  ##   ```
  ##   initial:
  ##     A
  ##     B
  ##   ```
  ##
  ## :param node: AST node of the state list declaration
  ## :returns: Sequence of state names
  result = @[]

  case node.kind
  of nnkCommand:
    # initial: A, B, C or initial A, B, C
    for i in 1 ..< node.len:
      let child = node[i]
      if child.kind == nnkStmtList:
        # Multiline block
        for item in child:
          if item.kind != nnkEmpty:
            result.add item.repr.strip(chars = {',', ' ', '\n'})
      else:
        result.add child.repr.strip(chars = {',', ' ', '\n'})
  of nnkCall:
    # initial: followed by StmtList
    if node.len >= 2 and node[1].kind == nnkStmtList:
      for item in node[1]:
        if item.kind != nnkEmpty:
          result.add item.repr.strip(chars = {',', ' ', '\n'})
    else:
      for i in 1 ..< node.len:
        result.add node[i].repr.strip(chars = {',', ' ', '\n'})
  else:
    error("Expected state list", node)

proc parseInitialBlock*(graph: var TypestateGraph, node: NimNode) =
  ## Parse the initial states block.
  ##
  ## Initial states can only be constructed, not transitioned to.
  ##
  ## Example input:
  ##
  ## ```nim
  ## initial: Disconnected
  ## # or
  ## initial: Disconnected, Starting
  ## # or
  ## initial:
  ##   Disconnected
  ##   Starting
  ## ```
  ##
  ## :param graph: The typestate graph to populate
  ## :param node: AST node of the initial block
  graph.initialStates = parseStateList(node)

proc parseTerminalBlock*(graph: var TypestateGraph, node: NimNode) =
  ## Parse the terminal states block.
  ##
  ## Terminal states are end states with no outgoing transitions.
  ##
  ## Example input:
  ##
  ## ```nim
  ## terminal: Closed
  ## # or
  ## terminal: Closed, Failed
  ## # or
  ## terminal:
  ##   Closed
  ##   Failed
  ## ```
  ##
  ## :param graph: The typestate graph to populate
  ## :param node: AST node of the terminal block
  graph.terminalStates = parseStateList(node)

proc paramName(typeParam: NimNode): string =
  ## Extract the name of a typeParam node.
  ##
  ## A typeParam is either a bare ident (`T`) or a constrained
  ## `nnkExprColonExpr` (`T: SomeInteger`). For constrained shapes the name
  ## is the first child; for bare idents the node itself carries the name.
  case typeParam.kind
  of nnkExprColonExpr:
    if typeParam[0].kind in {nnkIdent, nnkSym}:
      result = typeParam[0].strVal
    else:
      result = typeParam[0].repr
  of nnkIdent, nnkSym:
    result = typeParam.strVal
  else:
    result = typeParam.repr

proc parseDefaultsBlock*(graph: var TypestateGraph, node: NimNode) =
  ## Parse the optional `defaults:` body section.
  ##
  ## Captures default-value expressions for the typestate's bracket-head
  ## generic parameters. Defaults flow through `buildGenericParams` into
  ## every generated type and proc (state distincts, variant types, the
  ## context type, `=copy` hooks, `state()` procs, `$` overloads, etc.).
  ##
  ## Example input:
  ##
  ## ```nim
  ## typestate RegistrationContext[
  ##     MaxThreads: static int,
  ##     CC: static PinScopeCardinality]:
  ##   defaults:
  ##     CC: ccSingle
  ##   states:
  ##     Unregistered, Registered
  ## ```
  ##
  ## Validation rules (each rule fires a macro-time `error`):
  ##
  ## - Each entry must reference a generic param declared in the bracket
  ##   head; an unknown name is rejected with a clear message.
  ## - Each entry references only the param's name (no constraint
  ##   re-declaration). The constraint comes from the bracket head.
  ## - Duplicate entries (same param named twice) are rejected.
  ##
  ## The default-value expression is captured as-is (`NimNode`) and emitted
  ## verbatim at codegen; it is typed by the Nim compiler at the
  ## type-instantiation site, mirroring native `proc foo[T = Default]`
  ## semantics.
  ##
  ## :param graph: The typestate graph to populate
  ## :param node: AST node of the `defaults` block (nnkCall with StmtList body)
  if node.kind notin {nnkCall, nnkCommand}:
    error("defaults: expected a block of `ParamName: DefaultExpr` entries", node)

  # The body of a `defaults:` section is always a StmtList (the colon-block
  # form). Inline forms like `defaults: CC: ccSingle` collapse to the same
  # shape in Nim's AST: nnkCall(Ident "defaults", StmtList(...)).
  var body: NimNode = nil
  for i in 1 ..< node.len:
    if node[i].kind == nnkStmtList:
      body = node[i]
      break
  if body == nil:
    error(
      "defaults: section must use a colon-block body with " &
        "`ParamName: DefaultExpr` entries (e.g. `defaults:\\n  CC: ccSingle`)",
      node,
    )

  # Track the param names already given a default so duplicates are rejected.
  # Membership is tested with `eqIdent` (style-insensitive, per Nim's
  # identifier rules: first character case-sensitive, subsequent characters
  # case- and underscore-insensitive) so e.g. `MaxThreads` and `Maxthreads`
  # are treated as the same param rather than slipping through as two distinct
  # entries.
  var seenInDefaults: seq[NimNode]

  # Inside a StmtList, an entry written as `Name: Expr` parses to
  # `nnkCall(Ident "Name", StmtList(Expr))`, not `nnkExprColonExpr`. The
  # `nnkExprColonExpr` shape only appears when the colon-expr is inline in
  # an enclosing call (e.g. `defaults: CC: ccSingle` on a single line). Both
  # forms are accepted so the DSL reads naturally in either layout.
  for entry in body:
    # Skip empty nodes and standalone comments. A doc comment (`##`) written on
    # its own line inside the `defaults:` block survives parsing as a top-level
    # `nnkCommentStmt` child of the body (plain `#` line comments are stripped by
    # the parser and never reach here). Tolerate it rather than treating it as a
    # malformed entry. Mirrors the per-entry comment filter at the entry's value
    # StmtList below.
    if entry.kind in {nnkEmpty, nnkCommentStmt}:
      continue
    var nameNode: NimNode
    var defaultExpr: NimNode
    case entry.kind
    of nnkCall:
      # `Name: Expr` inside a StmtList -> nnkCall(name, StmtList(expr))
      if entry.len != 2 or entry[1].kind != nnkStmtList or entry[1].len == 0:
        error(
          "defaults: each entry must take the form `ParamName: DefaultExpr` " &
            "(got malformed nnkCall body)",
          entry,
        )
      nameNode = entry[0]
      # A `Name: Expr` entry's StmtList holds exactly one expression node.
      # Multiple statements under one name would mean the user wrote something
      # like `CC:\n  ccSingle\n  ccMulti` which is not a valid default.
      var nonEmptyChildren: seq[NimNode]
      for c in entry[1]:
        # Skip empty nodes and comments (doc `##` / line `#`) so a comment
        # between a param name and its default expression does not count as a
        # second expression. Mirrors the filter in codegen.nim.
        if c.kind notin {nnkEmpty, nnkCommentStmt}:
          nonEmptyChildren.add c
      if nonEmptyChildren.len != 1:
        error(
          "defaults: each entry must hold exactly one default expression. " & "Got " &
            $nonEmptyChildren.len & " expressions under '" & (
            if entry[0].kind in {nnkIdent, nnkSym}: entry[0].strVal
            else: entry[0].repr
          ) & "'.",
          entry,
        )
      defaultExpr = nonEmptyChildren[0]
    of nnkExprColonExpr:
      # Inline form `defaults: CC: ccSingle` on a single line.
      if entry.len != 2:
        error("defaults: each entry must take the form `ParamName: DefaultExpr`", entry)
      nameNode = entry[0]
      defaultExpr = entry[1]
    else:
      error(
        "defaults: each entry must take the form `ParamName: DefaultExpr` " &
          "(got node kind " & $entry.kind & ")",
        entry,
      )
    if nameNode.kind notin {nnkIdent, nnkSym}:
      error(
        "defaults: left-hand side must be a bare param name " &
          "(no constraint re-declaration; the constraint comes from the " &
          "bracket head). Got node kind " & $nameNode.kind & ".",
        nameNode,
      )
    let pname = nameNode.strVal
    # Resolve the entry's param name against the bracket-head params with a
    # style-insensitive linear scan (`eqIdent`), so a non-canonical spelling
    # (case/underscore variant) still binds. N params is tiny; linear search
    # is the idiomatic Nim-macro approach.
    var idx = -1
    for i, p in graph.typeParams:
      if eqIdent(nameNode, paramName(p)):
        idx = i
        break
    if idx < 0:
      var declared: seq[string]
      for p in graph.typeParams:
        declared.add paramName(p)
      let declaredStr =
        if declared.len > 0:
          declared.join(", ")
        else:
          "<none>"
      error(
        "defaults: '" & pname & "' does not match any generic param declared " &
          "in the typestate bracket head. Declared params: " & declaredStr & ".",
        nameNode,
      )
    # Duplicate detection is also style-insensitive: a second entry whose name
    # is `eqIdent`-equal to an already-seen one is a duplicate.
    var isDuplicate = false
    for seen in seenInDefaults:
      if eqIdent(seen, nameNode):
        isDuplicate = true
        break
    if isDuplicate:
      error(
        "defaults: '" & pname & "' is listed more than once. Each generic " &
          "param may have at most one default entry.",
        nameNode,
      )
    seenInDefaults.add nameNode
    graph.typeParamDefaults[idx] = defaultExpr.copyNimTree

proc validateUniqueBaseNames(graph: TypestateGraph, declNode: NimNode) =
  ## Validate that all states have unique base names.
  ##
  ## States must have distinct base type names because the library uses
  ## base names for enum generation, union types, and state matching.
  ## Using the same base type with different static parameters is not supported.
  ##
  ## Example that would fail:
  ##
  ## ```nim
  ## typestate GPIO[E: static bool]:
  ##   states GPIO[false], GPIO[true]  # ERROR: same base name "GPIO"
  ## ```
  ##
  ## Correct approach using wrapper types:
  ##
  ## ```nim
  ## type
  ##   GPIOBase[E: static bool] = object
  ##   Disabled = distinct GPIOBase[false]
  ##   Enabled = distinct GPIOBase[true]
  ##
  ## typestate GPIOBase[E: static bool]:
  ##   states Disabled, Enabled  # OK: different base names
  ## ```
  ##
  ## :param graph: The typestate graph to validate
  ## :param declNode: AST node for error reporting
  ## :raises: Compile-time error if duplicate base names found
  var baseNameCounts: seq[tuple[name: string, fullReprs: seq[string]]] = @[]

  for state in graph.states.values:
    var found = false
    for i in 0 ..< baseNameCounts.len:
      if baseNameCounts[i].name == state.name:
        baseNameCounts[i].fullReprs.add state.fullRepr
        found = true
        break
    if not found:
      baseNameCounts.add (name: state.name, fullReprs: @[state.fullRepr])

  for entry in baseNameCounts:
    if entry.fullReprs.len > 1:
      error(
        "Multiple states share the base name '" & entry.name & "': " &
          entry.fullReprs.join(", ") & "\n\n" &
          "States must have unique base type names. " &
          "Using the same type with different static parameters is not supported.\n\n" &
          "Use distinct wrapper types instead:\n" & "  type\n" & "    " & entry.name &
          "Base = object  # or your base type\n" & "    State1 = distinct " & entry.name &
          "Base\n" & "    State2 = distinct " & entry.name & "Base\n\n" &
          "See: https://elijahr.github.io/nim-typestates/guide/generics/",
        declNode,
      )

proc validateNoDuplicateBranchingSources(graph: TypestateGraph, declNode: NimNode) =
  ## Validate that each source state has at most one branching transition.
  ##
  ## Branching transitions (e.g., `Created -> Approved | Declined`) generate
  ## branch types like `CreatedBranch`. Multiple branching transitions from
  ## the same source would generate duplicate types.
  ##
  ## Example that would fail:
  ##
  ## ```nim
  ## transitions:
  ##   Created -> Approved | Declined  # Branching
  ##   Created -> Banana | Potato      # ERROR: duplicate branching source
  ## ```
  ##
  ## Non-branching transitions from the same source are allowed:
  ##
  ## ```nim
  ## transitions:
  ##   Created -> Approved | Declined  # Branching (OK)
  ##   Created -> Review               # Non-branching (OK, merged)
  ## ```
  ##
  ## :param graph: The typestate graph to validate
  ## :param declNode: AST node for error reporting
  ## :raises: Compile-time error if duplicate branching sources found
  var branchingSources: seq[string] = @[]

  for trans in graph.transitions:
    if trans.toStates.len > 1 and not trans.isWildcard:
      let source = extractBaseName(trans.fromState)
      if source in branchingSources:
        error(
          "Duplicate branching transition from '" & source & "'. " &
            "Each source state can only have one branching transition. " &
            "Combine destinations: " & source & " -> A | B | C",
          declNode,
        )
      branchingSources.add(source)

proc validateNoBranchTypeStateCollision(graph: TypestateGraph, declNode: NimNode) =
  ## Validate that no branching transition's wrapper type name collides with
  ## a declared state name.
  ##
  ## Branching transitions like `Created -> (Approved | Declined) as ApprovedResult`
  ## generate a wrapper type whose name (`ApprovedResult`) is used as the first
  ## parameter of a `match*` overload. v0.8.0 also generates per-state `match*`
  ## overloads keyed on each state name. If the wrapper name and a state name
  ## collide, two `match*` overloads with the same first-parameter type are
  ## emitted and Nim cannot disambiguate them.
  ##
  ## Example that would fail:
  ##
  ## ```nim
  ## states Created, Approved, Declined
  ## transitions:
  ##   Created -> (Approved | Declined) as Approved   # ERROR: collides with state Approved
  ## ```
  ##
  ## :param graph: The typestate graph to validate
  ## :param declNode: AST node for error reporting fallback location
  ## :raises: Compile-time error if a branch wrapper name collides with a state
  var stateBaseNames = initHashSet[string]()
  for state in graph.states.values:
    # state.name is already a base name (set by parseStates via extractBaseName).
    stateBaseNames.incl(state.name)

  for t in graph.transitions:
    if t.branchTypeName.len == 0:
      continue
    let wrapperBase = extractBaseName(t.branchTypeName)
    if wrapperBase in stateBaseNames:
      error(
        "Branch wrapper type name '" & wrapperBase & "' collides with state name '" &
          wrapperBase & "'. Use a distinct name (e.g., '" & wrapperBase & "Result'). " &
          "Transition declared at " & $t.declaredAt,
        declNode,
      )

proc validateInitialTerminal(graph: TypestateGraph, declNode: NimNode) =
  ## Validate that initial and terminal states are declared in states list.
  ##
  ## :param graph: The typestate graph to validate
  ## :param declNode: AST node for error reporting
  ## :raises: Compile-time error if initial/terminal states not in states list
  for s in graph.initialStates:
    let base = extractBaseName(s)
    var found = false
    for state in graph.states.values:
      if state.name == base or state.fullRepr == s:
        found = true
        break
    if not found:
      error("Initial state '" & s & "' is not in states list", declNode)

  for s in graph.terminalStates:
    let base = extractBaseName(s)
    var found = false
    for state in graph.states.values:
      if state.name == base or state.fullRepr == s:
        found = true
        break
    if not found:
      error("Terminal state '" & s & "' is not in states list", declNode)

proc validateTransitionsRespectInitialTerminal(
    graph: TypestateGraph, declNode: NimNode
) =
  ## Validate that transitions respect initial/terminal constraints.
  ##
  ## - Cannot transition TO an initial state
  ## - Cannot transition FROM a terminal state
  ##
  ## :param graph: The typestate graph to validate
  ## :param declNode: AST node for error reporting
  ## :raises: Compile-time error if constraints violated
  for t in graph.transitions:
    if not t.isWildcard:
      # Check FROM terminal
      if graph.isTerminalState(t.fromState):
        error(
          "Cannot declare transition FROM terminal state '" & t.fromState & "'",
          declNode,
        )

    # Check TO initial
    for dest in t.toStates:
      if graph.isInitialState(dest):
        error("Cannot declare transition TO initial state '" & dest & "'", declNode)

proc parseTypestateBody*(name: NimNode, body: NimNode): TypestateGraph =
  ## Parse a complete typestate block body into a TypestateGraph.
  ##
  ## This is the main entry point for parsing. It processes the full
  ## body of a `typestate` macro invocation.
  ##
  ## The typestate name can be a simple identifier or a generic type:
  ##
  ## - Simple: `typestate File:`
  ## - Generic: `typestate Container[T]:`
  ##
  ## Examples:
  ##
  ## ```nim
  ## typestate File:          # name = "File"
  ##   states Closed, Open
  ##   transitions:
  ##     Closed -> Open
  ##
  ## typestate Container[T]:  # name = "Container", with type param T
  ##   states Empty[T], Full[T]
  ##   transitions:
  ##     Empty[T] -> Full[T]
  ## ```
  ##
  ## :param name: The typestate name (identifier or bracket expression)
  ## :param body: The statement list containing states and transitions
  ## :returns: A fully populated `TypestateGraph`
  ## :raises: Compile-time error for invalid syntax

  # Extract base name and type params from name node
  var baseName: string
  var typeParams: seq[NimNode] = @[]

  if name.kind == nnkBracketExpr:
    # Generic: Container[T] or Map[K, V] or VirtualValueN[N: static int]
    baseName = extractBaseName(name[0])
    for i in 1 ..< name.len:
      typeParams.add name[i].copyNimTree
  else:
    # Simple: File
    baseName = extractBaseName(name)

  # Initialize defaults slot parallel to typeParams. Defaults remain
  # newEmptyNode() unless the typestate body contains a `defaults:` section.
  var typeParamDefaults: seq[NimNode] = @[]
  for _ in typeParams:
    typeParamDefaults.add newEmptyNode()

  result = TypestateGraph(
    name: baseName,
    typeParams: typeParams,
    typeParamDefaults: typeParamDefaults,
    declaredAt: name.lineInfoObj,
    declaredInModule: name.lineInfoObj.filename,
  )

  for child in body:
    case child.kind
    of nnkAsgn:
      parseFlag(result, child)
    of nnkCall, nnkCommand:
      # Guard `.strVal` against a non-identifier section header (e.g. a
      # parenthesized/complex callee like `(states)(Closed):`). Without this,
      # `child[0].strVal` raises an internal `node lacks field: strVal` compiler
      # error with a macro stack trace instead of a user-facing diagnostic.
      # Route any non-ident/sym callee to the same `Unknown section` error,
      # building the offending name from the kind-safe `.repr`.
      if child[0].kind notin {nnkIdent, nnkSym}:
        error("Unknown section in typestate block: " & child[0].repr, child)
      let sectionName = child[0].strVal
      # Dispatch on the section keyword with `eqIdent` (style-insensitive, per
      # Nim's identifier rules) so a non-canonical spelling (case/underscore
      # variant) still resolves. `sectionName` is retained for the unknown-
      # section error message.
      if child[0].eqIdent("states"):
        parseStates(result, child)
      elif child[0].eqIdent("transitions"):
        parseTransitionsBlock(result, child)
      elif child[0].eqIdent("bridges"):
        parseBridgesBlock(result, child)
      elif child[0].eqIdent("initial"):
        parseInitialBlock(result, child)
      elif child[0].eqIdent("terminal"):
        parseTerminalBlock(result, child)
      elif child[0].eqIdent("defaults"):
        parseDefaultsBlock(result, child)
      else:
        error("Unknown section in typestate block: " & sectionName, child)
    else:
      error("Unexpected node in typestate body: " & $child.kind, child)

  # Validate after all parsing is complete
  validateUniqueBaseNames(result, name)
  validateNoDuplicateBranchingSources(result, name)
  validateNoBranchTypeStateCollision(result, name)
  validateInitialTerminal(result, name)
  validateTransitionsRespectInitialTerminal(result, name)

  # Reachability/liveness analysis (opt-in: only fires when the user has
  # declared `initial:` or `terminal:`, so existing typestates produce no
  # warnings). Use `--define:typestatesNoReachabilityWarn` to silence even
  # when declared.
  when not defined(typestatesNoReachabilityWarn):
    if result.initialStates.len > 0 or result.terminalStates.len > 0:
      let report = analyzeReachability(result)
      for f in report.findings:
        let msg = formatFinding(f, report.initialStatesUsed, report.terminalStatesUsed)
        warning(msg, name)
