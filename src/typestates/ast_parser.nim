## AST-based parser for extracting typestate definitions from Nim source files.
##
## This module uses Nim's compiler infrastructure to parse source files
## accurately, handling comments, whitespace, and complex syntax correctly.
##
## Used by the CLI tool for project-wide verification.

import std/[os, strutils, options]

# Compiler imports - requires Nim compiler source
import compiler/[ast, parser, llstream, idents, options as compiler_options, pathutils]

type
  ParsedBridge* = object
    ## A bridge parsed from source code.
    fromState*: string
    toTypestate*: string
    toState*: string

  ParsedTransition* = object
    ## A transition parsed from source code.
    fromState*: string
    toStates*: seq[string]
    isWildcard*: bool

  ParsedTypestate* = object
    ## A typestate definition parsed from source code.
    name*: string
    states*: seq[string]
    transitions*: seq[ParsedTransition]
    bridges*: seq[ParsedBridge]
    isSealed*: bool
    strictTransitions*: bool

  ParseResult* = object
    ## Results from parsing source files.
    typestates*: seq[ParsedTypestate]
    filesChecked*: int

  ParseError* = object of CatchableError
    ## Error during parsing.

proc newParseError(msg: string): ref ParseError =
  result = newException(ParseError, msg)

proc extractIdent(node: PNode): string =
  ## Extract identifier string from a node.
  case node.kind
  of nkIdent:
    result = node.ident.s
  of nkSym:
    result = node.sym.name.s
  of nkPostfix:
    # Handle exported idents like `*ident`
    if node.len >= 2:
      result = extractIdent(node[1])
  else:
    result = ""

proc extractStates(node: PNode): seq[string] =
  ## Extract state names from a states declaration.
  ## Handles: states Closed, Open, Errored
  result = @[]

  if node.kind == nkCommand and node.len >= 2:
    let first = extractIdent(node[0])
    if first == "states":
      for i in 1 ..< node.len:
        let child = node[i]
        case child.kind
        of nkIdent:
          result.add child.ident.s
        of nkInfix:
          # Handle comma-separated: Closed, Open, Errored
          # In AST this appears as nested infix with `,` operator
          var current = child
          while current.kind == nkInfix and current.len >= 3:
            let op = extractIdent(current[0])
            if op == ",":
              # Right side is the last item or another infix
              let right = current[2]
              if right.kind == nkIdent:
                result.add right.ident.s
              # Recurse into left
              current = current[1]
            else:
              break
          if current.kind == nkIdent:
            result.add current.ident.s
        else:
          discard

proc extractTransition(node: PNode): Option[ParsedTransition] =
  ## Extract a transition from an infix or prefix node.
  ## Handles: Closed -> Open, Closed -> Open | Errored, * -> Closed
  ##
  ## Note: `* -> Stopped` is parsed as nested nkPrefix because `*` has higher
  ## precedence than `->`:
  ##   nkPrefix("*", nkPrefix("->", "Stopped"))

  var trans = ParsedTransition()
  var toNode: PNode

  # Handle wildcard case: nkPrefix("*", nkPrefix("->", dest))
  if node.kind == nkPrefix and node.len >= 2:
    let prefixOp = extractIdent(node[0])
    if prefixOp == "*" and node[1].kind == nkPrefix:
      let innerPrefix = node[1]
      if innerPrefix.len >= 2 and extractIdent(innerPrefix[0]) == "->":
        trans.fromState = "*"
        trans.isWildcard = true
        toNode = innerPrefix[1]
      else:
        return none(ParsedTransition)
    else:
      return none(ParsedTransition)

  # Handle normal case: nkInfix("->", from, to)
  elif node.kind == nkInfix and node.len >= 3:
    let op = extractIdent(node[0])
    if op != "->":
      return none(ParsedTransition)

    let fromNode = node[1]
    toNode = node[2]

    # Extract from state
    case fromNode.kind
    of nkIdent:
      trans.fromState = fromNode.ident.s
      trans.isWildcard = trans.fromState == "*"
    of nkPrefix:
      # Handle * (wildcard) - though this case may not occur with current grammar
      if fromNode.len >= 1 and extractIdent(fromNode[0]) == "*":
        trans.fromState = "*"
        trans.isWildcard = true
    else:
      return none(ParsedTransition)

  else:
    return none(ParsedTransition)

  # Extract to states (may be single or branching with |)
  trans.toStates = @[]

  proc collectToStates(n: PNode, states: var seq[string]) =
    case n.kind
    of nkIdent:
      states.add n.ident.s
    of nkInfix:
      let infixOp = extractIdent(n[0])
      if infixOp == "|" and n.len >= 3:
        collectToStates(n[1], states)
        collectToStates(n[2], states)
    else:
      discard

  collectToStates(toNode, trans.toStates)

  if trans.toStates.len > 0:
    return some(trans)
  else:
    return none(ParsedTransition)

proc extractTransitions(node: PNode): seq[ParsedTransition] =
  ## Extract transitions from a transitions block.
  result = @[]

  if node.kind == nkCall and node.len >= 1:
    let name = extractIdent(node[0])
    if name == "transitions":
      for i in 1 ..< node.len:
        let child = node[i]
        if child.kind == nkStmtList:
          for stmt in child:
            let trans = extractTransition(stmt)
            if trans.isSome:
              result.add trans.get
        else:
          let trans = extractTransition(child)
          if trans.isSome:
            result.add trans.get

proc extractBridge(node: PNode): Option[ParsedBridge] =
  ## Extract a bridge from an infix or prefix node.
  ## Handles: Authenticated -> Session.Active, * -> Shutdown.Terminal
  ##
  ## Note: `* -> Session.Active` is parsed as nested nkPrefix.

  var bridge = ParsedBridge()
  var toNode: PNode

  # Handle wildcard case: nkPrefix("*", nkPrefix("->", dest))
  if node.kind == nkPrefix and node.len >= 2:
    let prefixOp = extractIdent(node[0])
    if prefixOp == "*" and node[1].kind == nkPrefix:
      let innerPrefix = node[1]
      if innerPrefix.len >= 2 and extractIdent(innerPrefix[0]) == "->":
        bridge.fromState = "*"
        toNode = innerPrefix[1]
      else:
        return none(ParsedBridge)
    else:
      return none(ParsedBridge)

  # Handle normal case: nkInfix("->", from, to)
  elif node.kind == nkInfix and node.len >= 3:
    let op = extractIdent(node[0])
    if op != "->":
      return none(ParsedBridge)

    let fromNode = node[1]
    toNode = node[2]

    # Extract from state
    case fromNode.kind
    of nkIdent:
      bridge.fromState = fromNode.ident.s
    of nkPrefix:
      if fromNode.len >= 1 and extractIdent(fromNode[0]) == "*":
        bridge.fromState = "*"
    else:
      return none(ParsedBridge)

  else:
    return none(ParsedBridge)

  # Extract destination: must be nkDotExpr (Typestate.State)
  if toNode.kind != nkDotExpr or toNode.len < 2:
    return none(ParsedBridge)

  bridge.toTypestate = extractIdent(toNode[0])
  bridge.toState = extractIdent(toNode[1])

  if bridge.toTypestate != "" and bridge.toState != "":
    return some(bridge)
  else:
    return none(ParsedBridge)

proc extractBridges(node: PNode): seq[ParsedBridge] =
  ## Extract bridges from a bridges block.
  result = @[]

  if node.kind == nkCall and node.len >= 1:
    let name = extractIdent(node[0])
    if name == "bridges":
      for i in 1 ..< node.len:
        let child = node[i]
        if child.kind == nkStmtList:
          for stmt in child:
            let bridge = extractBridge(stmt)
            if bridge.isSome:
              result.add bridge.get
        else:
          let bridge = extractBridge(child)
          if bridge.isSome:
            result.add bridge.get

proc extractFlag(node: PNode, flagName: string): Option[bool] =
  ## Extract a boolean flag assignment.
  ## Handles: isSealed = false, strictTransitions = true
  if node.kind == nkAsgn and node.len >= 2:
    let name = extractIdent(node[0])
    if name == flagName:
      let value = node[1]
      if value.kind == nkIdent:
        case value.ident.s
        of "true":
          return some(true)
        of "false":
          return some(false)
  return none(bool)

proc parseTypestateNode(node: PNode): Option[ParsedTypestate] =
  ## Parse a typestate macro call node.
  ## Expects: typestate Name: body
  if node.kind notin {nkCommand, nkCall}:
    return none(ParsedTypestate)

  if node.len < 2:
    return none(ParsedTypestate)

  let macroName = extractIdent(node[0])
  if macroName != "typestate":
    return none(ParsedTypestate)

  var ts = ParsedTypestate(
    isSealed: true,  # Default
    strictTransitions: true  # Default
  )

  # Second node is the name (might be in a call with colon)
  let nameNode = node[1]
  case nameNode.kind
  of nkIdent:
    ts.name = nameNode.ident.s
  of nkCall:
    # typestate Name: ...
    if nameNode.len >= 1:
      ts.name = extractIdent(nameNode[0])
  else:
    return none(ParsedTypestate)

  if ts.name == "":
    return none(ParsedTypestate)

  # Parse body (statement list)
  proc parseBody(body: PNode, ts: var ParsedTypestate) =
    for child in body:
      # Check for states declaration
      let states = extractStates(child)
      if states.len > 0:
        ts.states = states

      # Check for transitions block
      let transitions = extractTransitions(child)
      if transitions.len > 0:
        ts.transitions.add transitions

      # Check for bridges block
      let bridges = extractBridges(child)
      if bridges.len > 0:
        ts.bridges.add bridges

      # Check for flags
      let sealedFlag = extractFlag(child, "isSealed")
      if sealedFlag.isSome:
        ts.isSealed = sealedFlag.get

      let strictFlag = extractFlag(child, "strictTransitions")
      if strictFlag.isSome:
        ts.strictTransitions = strictFlag.get

      # Recurse into nested statement lists
      if child.kind == nkStmtList:
        parseBody(child, ts)

  # Body is in remaining nodes or in a call structure
  for i in 1 ..< node.len:
    let child = node[i]
    if child.kind == nkStmtList:
      parseBody(child, ts)
    elif child.kind == nkCall and child.len >= 2:
      # Handle typestate Name: where body is in the call
      if child[1].kind == nkStmtList:
        parseBody(child[1], ts)

  if ts.states.len > 0:
    return some(ts)
  else:
    return none(ParsedTypestate)

proc walkAst(node: PNode, typestates: var seq[ParsedTypestate]) =
  ## Walk the AST looking for typestate definitions.
  if node == nil:
    return

  # Try to parse this node as a typestate
  let ts = parseTypestateNode(node)
  if ts.isSome:
    typestates.add ts.get
    return  # Don't recurse into typestate body

  # Recurse into children
  for child in node:
    walkAst(child, typestates)

proc parseFileWithAst*(path: string): ParseResult =
  ## Parse a Nim file using the compiler's AST parser.
  ##
  ## Raises ParseError if the file cannot be parsed.
  result = ParseResult()
  result.filesChecked = 1

  if not fileExists(path):
    raise newParseError("File not found: " & path)

  let content = readFile(path)
  let absPath = AbsoluteFile(path.absolutePath)

  # Create parser infrastructure
  let cache = newIdentCache()
  let config = newConfigRef()

  # Configure for minimal output
  config.notes = {}
  config.foreignPackageNotes = {}

  var p: Parser
  let stream = llStreamOpen(content)
  if stream == nil:
    raise newParseError("Failed to open stream for: " & path)

  try:
    openParser(p, absPath, stream, cache, config)
    let ast = parseAll(p)
    closeParser(p)

    # Walk AST looking for typestates
    walkAst(ast, result.typestates)
  except Exception as e:
    raise newParseError("Parse error in " & path & ": " & e.msg)

proc parseTypestatesAst*(paths: seq[string]): ParseResult =
  ## Parse all Nim files in the given paths for typestates.
  ##
  ## Fails loudly on any parse error.
  result = ParseResult()

  for path in paths:
    if path.endsWith(".nim"):
      let fileResult = parseFileWithAst(path)
      result.typestates.add fileResult.typestates
      result.filesChecked += fileResult.filesChecked
    elif dirExists(path):
      for file in walkDirRec(path):
        if file.endsWith(".nim"):
          let fileResult = parseFileWithAst(file)
          result.typestates.add fileResult.typestates
          result.filesChecked += fileResult.filesChecked
