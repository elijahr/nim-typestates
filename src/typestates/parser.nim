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

import std/[macros, tables, strutils]
import types

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
        graph.states[fullRepr] = State(
          name: baseName,
          fullRepr: fullRepr,
          typeName: stateNode
        )
    else:
      # Inline: each child is a state
      let baseName = extractBaseName(child)
      let fullRepr = child.repr
      graph.states[fullRepr] = State(
        name: baseName,
        fullRepr: fullRepr,
        typeName: child
      )

proc collectBranchTargets(node: NimNode): seq[string] =
  ## Recursively collect all target states from a branching expression.
  ##
  ## Handles the `|` operator for branching transitions like `Open | Errored`.
  ## States can be any valid type expression (simple, generic, ref, etc.).
  ##
  ## Examples:
  ##
  ## - `Open` -> `@["Open"]`
  ## - `Open | Errored` -> `@["Open", "Errored"]`
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
        declaredAt: node.lineInfoObj
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
    error("Branching transitions require a result type name. " &
          "Use: " & fromState & " -> " & toStates.join(" | ") & " as ResultTypeName",
          node)

  # Validate: non-branching transitions should NOT have a type name
  if toStates.len == 1 and branchTypeName != "":
    error("Non-branching transition should not have 'as " & branchTypeName & "'. " &
          "The 'as TypeName' syntax is only for branching transitions (A -> B | C).",
          node)

  result = Transition(
    fromState: fromState,
    toStates: toStates,
    branchTypeName: branchTypeName,
    branchTypeNode: branchTypeNode,
    isWildcard: isWildcard,
    declaredAt: node.lineInfoObj
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
  else:
    error("Unknown flag: " & flagName & ". Valid flags: strictTransitions, consumeOnTransition", node)

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

proc collectBridgeTargets(node: NimNode): seq[tuple[typestate: string, state: string]] =
  ## Recursively collect all target typestates/states from a branching expression.
  ##
  ## Handles the `|` operator for branching bridges like `Session.Active | Session.Guest`.
  ##
  ## Examples:
  ##
  ## - `Session.Active` -> `@[("Session", "Active")]`
  ## - `Session.Active | Session.Guest` -> `@[("Session", "Active"), ("Session", "Guest")]`
  ##
  ## :param node: AST node representing the target(s)
  ## :returns: Sequence of (typestate, state) tuples
  case node.kind
  of nnkDotExpr:
    let typestate = extractBaseName(node[0])
    let state = extractBaseName(node[1])
    result = @[(typestate, state)]
  of nnkInfix:
    if node[0].strVal == "|":
      result = collectBridgeTargets(node[1]) & collectBridgeTargets(node[2])
    else:
      error("Expected '|' in branching bridge", node)
  else:
    error("Bridge destination must use dotted notation (Typestate.State)", node)

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
        toTypestate: target.typestate,
        toState: target.state,
        declaredAt: child.lineInfoObj
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
    for i in 1..<node.len:
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
      for i in 1..<node.len:
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
    for i in 0..<baseNameCounts.len:
      if baseNameCounts[i].name == state.name:
        baseNameCounts[i].fullReprs.add state.fullRepr
        found = true
        break
    if not found:
      baseNameCounts.add (name: state.name, fullReprs: @[state.fullRepr])

  for entry in baseNameCounts:
    if entry.fullReprs.len > 1:
      error("Multiple states share the base name '" & entry.name & "': " &
            entry.fullReprs.join(", ") & "\n\n" &
            "States must have unique base type names. " &
            "Using the same type with different static parameters is not supported.\n\n" &
            "Use distinct wrapper types instead:\n" &
            "  type\n" &
            "    " & entry.name & "Base = object  # or your base type\n" &
            "    State1 = distinct " & entry.name & "Base\n" &
            "    State2 = distinct " & entry.name & "Base\n\n" &
            "See: https://elijahr.github.io/nim-typestates/guide/generics/", declNode)

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
        error("Duplicate branching transition from '" & source & "'. " &
              "Each source state can only have one branching transition. " &
              "Combine destinations: " & source & " -> A | B | C", declNode)
      branchingSources.add(source)

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

proc validateTransitionsRespectInitialTerminal(graph: TypestateGraph, declNode: NimNode) =
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
        error("Cannot declare transition FROM terminal state '" & t.fromState & "'", declNode)

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
    for i in 1..<name.len:
      typeParams.add name[i].copyNimTree
  else:
    # Simple: File
    baseName = extractBaseName(name)

  result = TypestateGraph(
    name: baseName,
    typeParams: typeParams,
    declaredAt: name.lineInfoObj,
    declaredInModule: name.lineInfoObj.filename
  )

  for child in body:
    case child.kind
    of nnkAsgn:
      parseFlag(result, child)
    of nnkCall, nnkCommand:
      let sectionName = child[0].strVal
      case sectionName
      of "states":
        parseStates(result, child)
      of "transitions":
        parseTransitionsBlock(result, child)
      of "bridges":
        parseBridgesBlock(result, child)
      of "initial":
        parseInitialBlock(result, child)
      of "terminal":
        parseTerminalBlock(result, child)
      else:
        error("Unknown section in typestate block: " & sectionName, child)
    else:
      error("Unexpected node in typestate body: " & $child.kind, child)

  # Validate after all parsing is complete
  validateUniqueBaseNames(result, name)
  validateNoDuplicateBranchingSources(result, name)
  validateInitialTerminal(result, name)
  validateTransitionsRespectInitialTerminal(result, name)
