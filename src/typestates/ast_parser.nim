## AST-based parser for extracting typestate definitions from Nim source files.
##
## This module uses Nim's compiler infrastructure to parse source files
## accurately, handling comments, whitespace, and complex syntax correctly.
##
## Used by the CLI tool for project-wide verification.

import std/[os, strutils, options, sets, tables]

import ./types # extractBaseName, used as final normalizer in peelToBaseTypeName

# Compiler imports - requires Nim compiler source
import
  compiler/[
    ast,
    parser,
    llstream,
    idents,
    options as compiler_options,
    pathutils,
    renderer,
    lineinfos,
    lexer,
    msgs,
  ]

type
  ParsedBridge* = object ## A bridge parsed from source code.
    fromState*: string
    toTypestate*: string
    toState*: string
    fullDestRepr*: string
      ## Full destination representation (e.g., "Session.Active" or "module.Typestate.State")

  ParsedTransition* = object ## A transition parsed from source code.
    fromState*: string
    toStates*: seq[string]
    isWildcard*: bool

  ParsedTypestate* = object ## A typestate definition parsed from source code.
    name*: string
    states*: seq[string]
    transitions*: seq[ParsedTransition]
    bridges*: seq[ParsedBridge]
    isSealed*: bool
    strictTransitions*: bool
    opaqueStates*: bool ## Opt-in CLI lint for raw distinct casts to non-initial states
    initialStates*: seq[string] ## States declared in `initial:` block
    terminalStates*: seq[string] ## States declared in `terminal:` block

  ParseFailure* = object
    ## A single per-file parse failure, carrying enough structured data
    ## to materialize an `fcParseError` Finding without re-parsing the
    ## formatted message string. `path` is the absolute or
    ## as-supplied-by-the-caller path; `line` and `column` are 1-indexed
    ## (`0` if not applicable). `message` is the bare diagnostic (no
    ## embedded path/line prefix — that data lives in `path`/`line`/
    ## `column`). Round-3 review fix: added `column` so col data flows
    ## through to `Finding` without re-parsing `message`.
    path*: string
    line*: int
    column*: int
    message*: string

  ParseResult* = object
    ## Results from parsing source files.
    ##
    ## `typestates` and `filesChecked` cover only the files that parsed
    ## successfully. Files that failed to parse are reported via
    ## `failures` (one entry per failed file). v0.7+ callers that want to
    ## report parse errors as structured findings instead of aborting the
    ## pipeline should iterate `failures` and emit one
    ## `fcParseError` per entry.
    typestates*: seq[ParsedTypestate]
    filesChecked*: int
    failures*: seq[ParseFailure]

  ParseError* = object of CatchableError
    ## Error during parsing.
    ##
    ## Carries structured location data so consumers (e.g. `verify()`,
    ## `lintOpaqueStates`) can build `Finding` records without re-parsing the
    ## formatted message. `path` is the absolute path of the offending file
    ## (or `""` when unknown, e.g. file-not-found pre-parse). `line` is
    ## 1-indexed; `column` is 1-indexed. `0` for either means "not
    ## applicable / unknown". The `msg` field still carries the human
    ## formatted diagnostic for backwards compatibility.
    path*: string
    line*: int
    column*: int

proc newParseError(
    msg: string, path: string = "", line: int = 0, column: int = 0
): ref ParseError =
  result = newException(ParseError, msg)
  result.path = path
  result.line = line
  result.column = column

proc recordFailure(pr: var ParseResult, fallbackPath: string, e: ref ParseError) =
  ## Append a `ParseFailure` for one failed file to `pr.failures`.
  ##
  ## Hoisted (Gemini medium) from two byte-identical nested copies that lived
  ## inside `parseTypestatesAst` and `parseTypestatesAstWithNodes`. Prefers the
  ## structured `e.path` and falls back to the as-encountered `fallbackPath`
  ## when the error carries no path (e.g. a file-not-found raised before parse).
  ##
  ## Defensive nil guard (Gemini round-2 Finding 2): no current call site
  ## passes `nil`, but future refactors might (e.g. an `except CatchableError`
  ## branch that forgets to construct a `ParseError`). Without the guard,
  ## dereferencing `e.path` would crash with a hard SIGSEGV instead of
  ## producing a useful failure record. Synthesize a placeholder failure
  ## describing the missing exception so the caller still gets a structured
  ## diagnostic.
  if e == nil:
    pr.failures.add ParseFailure(
      path: fallbackPath,
      line: 0,
      column: 0,
      message: "internal error: recordFailure called with nil exception",
    )
    return
  let p = if e.path.len > 0: e.path else: fallbackPath
  pr.failures.add ParseFailure(path: p, line: e.line, column: e.column, message: e.msg)

proc raisingErrorHandler(
    conf: ConfigRef, info: TLineInfo, msg: TMsgKind, arg: string
) {.gcsafe.} =
  ## Lexer/parser error hook that converts Nim's compiler-internal
  ## "print + quit(1)" diagnostic path into a catchable `ParseError`.
  ##
  ## Without this hook the default `msgs.message` writes to stderr and calls
  ## `quit(1)` from `handleError` (see compiler/msgs.nim) before any
  ## `try/except ParseError` in `parsePNode` can fire, killing the host
  ## process. With this hook installed, `verify()` can convert the failure
  ## into an `fcParseError` Finding and route it through the JSON / GitHub
  ## formatters.
  ##
  ## The raised `ParseError` carries structured `path`/`line`/`column`
  ## fields so callers can build `Finding` records directly without parsing
  ## the formatted message string. `msg` is just the bare diagnostic — the
  ## structured location fields carry path/line/column, so embedding them
  ## in `msg` would cause `formatHuman` to render `path:line - path(line,
  ## col) Error: <arg>` (path/line repeated). Round-3 review fix: drop the
  ## location prefix from `msg`.
  let path =
    try:
      conf.toFullPath(info.fileIndex)
    except CatchableError:
      "<unknown>"
  let e = newException(ParseError, arg)
  e.path = path
  e.line = int(info.line)
  e.column = int(info.col + 1)
  raise e

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
  of nkAccQuoted:
    # Backticked / operator names (`` `[]` ``, `` `==` ``) parse as
    # `nkAccQuoted`. Render to the operator/identifier text so callers (notably
    # `routineName`) get a sensible symbol instead of an empty string. Because
    # `nkPostfix` recurses here, this also covers the EXPORTED backticked shape
    # (`nkPostfix[nkIdent("*"), nkAccQuoted]`) that the prior cycle's
    # top-level-only check missed. Other `extractIdent` callers (type names,
    # pragma markers) never see `nkAccQuoted` — those node shapes are never
    # backticked — so this branch is inert for them.
    result = renderTree(node, {})
  else:
    result = ""

proc extractStateName(node: PNode): string =
  ## Extract a state name from a node, handling both simple idents and generics.
  case node.kind
  of nkIdent:
    result = node.ident.s
  of nkBracketExpr:
    # Generic state like Unpinned[MaxThreads] - use full repr
    result = renderTree(node, {})
  else:
    result = ""

proc extractStates(node: PNode): seq[string] =
  ## Extract state names from a states declaration.
  ## Handles: states Closed, Open, Errored
  ## Handles: states Unpinned[MaxThreads], Pinned[MaxThreads]
  result = @[]

  if node.kind == nkCommand and node.len >= 2:
    let first = extractIdent(node[0])
    if first == "states":
      for i in 1 ..< node.len:
        let child = node[i]
        case child.kind
        of nkIdent:
          result.add child.ident.s
        of nkBracketExpr:
          # Generic state: Unpinned[MaxThreads]
          result.add renderTree(child, {})
        of nkInfix:
          # Handle comma-separated: Closed, Open, Errored
          # In AST this appears as nested infix with `,` operator
          var current = child
          while current.kind == nkInfix and current.len >= 3:
            let op = extractIdent(current[0])
            if op == ",":
              # Right side is the last item or another infix
              let right = current[2]
              let name = extractStateName(right)
              if name != "":
                result.add name
              # Recurse into left
              current = current[1]
            else:
              break
          let name = extractStateName(current)
          if name != "":
            result.add name
        else:
          discard

proc collectStateIdents(node: PNode, out_states: var seq[string]) =
  ## Walk a node tree and collect state names.
  ##
  ## Handles nkIdent, nkBracketExpr (generic states like `Pinned[T]`), nested
  ## nkInfix("," , left, right) chains for comma-separated lists, and nkStmtList
  ## for multi-line block bodies. Symmetric with how `extractStates` handles its
  ## children for the `states` keyword.
  if node == nil:
    return
  case node.kind
  of nkIdent:
    out_states.add node.ident.s
  of nkBracketExpr:
    out_states.add renderTree(node, {})
  of nkInfix:
    # Nested comma chain: e.g. `A, B, C` parses as nkInfix(",", nkInfix(",", A, B), C)
    if node.len >= 3 and extractIdent(node[0]) == ",":
      collectStateIdents(node[1], out_states)
      collectStateIdents(node[2], out_states)
  of nkStmtList:
    for child in node:
      collectStateIdents(child, out_states)
  else:
    discard

proc extractInitialStates(node: PNode): seq[string] =
  ## Extract state names from `initial: A` or `initial: A, B` or
  ## `initial:` (with multi-line indented body).
  ##
  ## Reference shape from `extractStates` (lines ~70-107):
  ##   if node.kind == nkCommand and node.len >= 2:
  ##     let first = extractIdent(node[0])
  ##     if first == "states":
  ##       for i in 1 ..< node.len:
  ##         case child.kind
  ##         of nkIdent: result.add child.ident.s
  ##         of nkBracketExpr: result.add renderTree(child, {})
  ##         of nkInfix: # comma chain ...
  ##
  ## The `initial:` keyword shows up as nkCall when followed by a `:` block
  ## (multi-line) and as nkCommand when used inline (`initial: A`). Both forms
  ## are tolerated here.
  result = @[]
  if node.kind notin {nkCommand, nkCall}:
    return
  if node.len < 2:
    return
  let kw = extractIdent(node[0])
  if kw != "initial":
    return
  for i in 1 ..< node.len:
    collectStateIdents(node[i], result)

proc extractTerminalStates(node: PNode): seq[string] =
  ## Extract state names from `terminal: A` / `terminal: A, B` /
  ## `terminal:` block. Symmetric with `extractInitialStates`.
  result = @[]
  if node.kind notin {nkCommand, nkCall}:
    return
  if node.len < 2:
    return
  let kw = extractIdent(node[0])
  if kw != "terminal":
    return
  for i in 1 ..< node.len:
    collectStateIdents(node[i], result)

proc extractTransition(node: PNode): Option[ParsedTransition] =
  ## Extract a transition from an infix or prefix node.
  ## Handles: Closed -> Open, Closed -> (Open | Errored), * -> Closed
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
    of nkBracketExpr:
      # Generic state: Unpinned[MaxThreads]
      trans.fromState = renderTree(fromNode, {})
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
  # Also handles "as TypeName" suffix: A | B as TypeName
  # In that case the structure is: nkInfix("as", nkInfix("|", A, B), TypeName)
  trans.toStates = @[]

  proc collectToStates(n: PNode, states: var seq[string]) =
    case n.kind
    of nkIdent:
      states.add n.ident.s
    of nkBracketExpr:
      # Generic state: Pinned[MaxThreads]
      states.add renderTree(n, {})
    of nkInfix:
      let infixOp = extractIdent(n[0])
      if infixOp == "|" and n.len >= 3:
        collectToStates(n[1], states)
        collectToStates(n[2], states)
      elif infixOp == "as" and n.len >= 3:
        # Skip the type name (n[2]), recurse into the states (n[1])
        collectToStates(n[1], states)
    of nkPar:
      # Parenthesized expression like (A | B) - unwrap and recurse
      if n.len == 1:
        collectToStates(n[0], states)
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

  # Extract destination: must be nkDotExpr (Typestate.State or module.Typestate.State)
  if toNode.kind != nkDotExpr or toNode.len < 2:
    return none(ParsedBridge)

  # Check if this is a nested DotExpr (module.Typestate.State)
  if toNode[0].kind == nkDotExpr:
    # Nested: module.Typestate.State
    # toNode[0] = module.Typestate (DotExpr)
    # toNode[1] = State (Ident)
    bridge.toTypestate = extractIdent(toNode[0][1]) # Get Typestate from module.Typestate
    bridge.toState = extractIdent(toNode[1]) # Get State
  else:
    # Simple: Typestate.State
    bridge.toTypestate = extractIdent(toNode[0])
    bridge.toState = extractIdent(toNode[1])

  # Build fullDestRepr from the node's representation
  # This captures the full syntax as written (Typestate.State or module.Typestate.State)
  bridge.fullDestRepr = renderTree(toNode, {})

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
    isSealed: true, # Default
    strictTransitions: true, # Default
  )

  # Second node is the name (might be in a call with colon, or generic)
  let nameNode = node[1]
  case nameNode.kind
  of nkIdent:
    ts.name = nameNode.ident.s
  of nkCall:
    # typestate Name: ...
    if nameNode.len >= 1:
      let inner = nameNode[0]
      case inner.kind
      of nkIdent:
        ts.name = inner.ident.s
      of nkBracketExpr:
        # typestate Name[T]: ... - extract base name
        ts.name = extractIdent(inner[0])
      else:
        ts.name = extractIdent(inner)
  of nkBracketExpr:
    # typestate Name[T] (without colon on same line)
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

      # Check for initial: / terminal: blocks
      let initials = extractInitialStates(child)
      if initials.len > 0:
        ts.initialStates.add initials
      let terminals = extractTerminalStates(child)
      if terminals.len > 0:
        ts.terminalStates.add terminals

      # Check for flags
      let sealedFlag = extractFlag(child, "isSealed")
      if sealedFlag.isSome:
        ts.isSealed = sealedFlag.get

      let strictFlag = extractFlag(child, "strictTransitions")
      if strictFlag.isSome:
        ts.strictTransitions = strictFlag.get

      let opaqueFlag = extractFlag(child, "opaqueStates")
      if opaqueFlag.isSome:
        ts.opaqueStates = opaqueFlag.get

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
    return # Don't recurse into typestate body

  # Recurse into children
  for child in node:
    walkAst(child, typestates)

# ---------------------------------------------------------------------------
# Pure PNode classification helpers (v0.9.4 AST verifier building blocks)
#
# These operate on raw compiler `PNode` trees (the `compiler/ast` API), NOT
# `std/macros` `NimNode`. They are the read-only classification primitives the
# AST-based verifier rewrite will use to categorize routines as transitions,
# non-transitions, or unmarked, and to resolve typestate parameter base types.
#
# PNode immutability (Tier-B note): every helper below only READS the tree
# (field access, `len`, indexing, iteration via `items`). None mutate `PNode`
# in place, so a single parse can be shared across all consumers safely.
# ---------------------------------------------------------------------------

type ProcClass* = enum
  ## Classification of a routine definition by its typestate marker pragmas.
  pcTransition ## Carries `{.transition.}` or `{.destructorTransition.}`.
  pcNotATransition ## Carries `{.notATransition.}` (and no transition marker).
  pcUnmarked ## Carries neither marker.

const routineContainerKinds = {
  # Statement lists (module body, and the implicit list inside every
  # control-structure branch / block / pragma body).
  nkStmtList,
  nkStmtListExpr,
  # `when` structure and its branches.
  nkWhenStmt,
  nkElifBranch,
  nkElifExpr,
  nkElse,
  nkElseExpr,
  # `if`/`case` structures and their branches. Branch bodies wrap routines in
  # an inner `nkStmtList`, but the branch/selector node itself must be descended
  # to reach that list (empirically confirmed: a `case`/`of` with a routine was
  # silently skipped before `nkCaseStmt`/`nkOfBranch` were added).
  nkIfStmt,
  nkIfExpr,
  nkCaseStmt,
  nkOfBranch,
  # `block` statements/expressions and `static`/`defer` bodies.
  nkBlockStmt,
  nkBlockExpr,
  nkStaticStmt,
  nkDefer,
  # `try` structure and its branches.
  nkTryStmt,
  nkExceptBranch,
  nkFinally,
  # Block-pragma sections (`{.cast(gcsafe).}:`, `{.push.}:` block form): the
  # routine is nested as `nkPragmaBlock -> nkStmtList -> routine`, so the
  # outer `nkPragmaBlock` must be descended. NOTE: flat `{.push.}` / `{.pop.}`
  # (the statement form) parse as `nkPragma` SIBLINGS of the routine inside the
  # surrounding `nkStmtList` and are already handled by the normal sibling walk;
  # no `nkPragma` handling is needed or added here.
  nkPragmaBlock,
}
  ## Statement-container node kinds that can wrap a module-scope routine
  ## definition at the SAME logical scope without being a routine body.
  ## `collectRoutineDefs` descends exactly these. Named const so the full
  ## audited set lives in one place and future omissions are less likely.

proc collectRoutineDefs*(node: PNode, acc: var seq[PNode]) =
  ## Recursively collect `nkProcDef` and `nkFuncDef` nodes into `acc`.
  ##
  ## Descends every *statement-container* node in `routineContainerKinds` —
  ## every node kind that can wrap a routine definition at the SAME logical
  ## scope without being a routine body (statement lists, `when`/`if`/`case`
  ## structures and their branches, `block`/`static`/`defer` bodies, `try`
  ## structures, and block-pragma sections). This widening (Gemini medium)
  ## closes the silent-skip gap: a typestate-parameter routine defined inside
  ## e.g. `static:` / `block:` / `try:` / a `{.cast(gcsafe).}:` block or a
  ## `case`/`of` branch was previously missed — exactly the silent-skip class
  ## this AST rewrite exists to eliminate.
  ##
  ## Does NOT descend into routine bodies (`nkProcDef`/`nkFuncDef` children),
  ## so nested procs are not collected — preserving the module-scope intent and
  ## matching the prior text scanner, which saw routine HEADERS regardless of
  ## the control structure wrapping them but did not pull out procs nested
  ## inside another proc's body. Methods, converters, templates, and macros are
  ## intentionally out of scope and are not collected.
  if node == nil:
    return
  case node.kind
  of nkProcDef, nkFuncDef:
    acc.add node
    # Do not descend into the body: nested routines are out of scope.
  of routineContainerKinds:
    for child in node:
      collectRoutineDefs(child, acc)
  else:
    discard

const peelableModifierTyKinds = {
  # Dedicated single-child modifier *type* nodes that wrap a parameter type and
  # carry no name of their own — peel straight into the wrapped child `[0]`.
  #
  # Empirically audited against the Nim 2.2.x compiler (treeRepr dumps of real
  # parameter-position parses; see the v0.10.0 AST-verifier audit):
  #   - `var T`  -> nkVarTy(T)
  #   - `ptr T`  -> nkPtrTy(T)
  #   - `ref T`  -> nkRefTy(T)
  #   - `out T`  -> nkOutTy(T)   (was MISSED before this set: fell through to the
  #                               render fallback and resolved to "out T")
  # All four nest cleanly (`var ptr T` -> nkVarTy(nkPtrTy(T))) and recurse here.
  #
  # NOT in this set, by empirical finding (Gemini medium asked to add nkLentTy):
  #   - `nkLentTy` does NOT EXIST in the Nim 2.2.x TNodeKind enum, and in
  #     PARAMETER position `lent T` / `sink T` parse as
  #     `nkCommand(nkIdent("lent"|"sink"), T)`, handled by the nkCommand branch
  #     below — NOT as a dedicated type node. Adding `nkLentTy` here would fail
  #     to compile. Do not reintroduce it.
  #   - `nkDistinctTy` is intentionally never peeled (a distinct is a NEW type);
  #     handled separately below.
  nkVarTy,
  nkRefTy,
  nkPtrTy,
  nkOutTy,
}
  ## Dedicated single-child modifier type-node kinds that `peelToBaseTypeName`
  ## peels uniformly. Named const so the full audited set lives in one place and
  ## future omissions are less likely (mirrors the `routineContainerKinds`
  ## pattern).

proc peelToBaseTypeName*(node: PNode): string =
  ## Peel parameter-passing wrappers and generic brackets to a base type name.
  ##
  ## Handles (recursively / idempotently regardless of ordering):
  ## - dedicated modifier type nodes in `peelableModifierTyKinds`
  ##   (`nkVarTy` / `nkRefTy` / `nkPtrTy` / `nkOutTy`) -> peel into the wrapped
  ##   type
  ## - `sink T` / `lent T` (parsed by the compiler in parameter position as
  ##   `nkCommand(nkIdent("sink"|"lent"), T)`) -> peel to `T`
  ## - `nkBracketExpr` (generics like `Stage1[T]`, `PinnedScope[MT, CC]`)
  ##   -> recurse into the head `[0]` to get the base
  ## - `nkIdent` -> the identifier string
  ## - `nkDotExpr` (e.g. `module.State`) -> the last (rightmost) component
  ##
  ## Distinct types are NOT peeled: a `distinct T` is a NEW type. A bare inline
  ## `nkDistinctTy` has no name of its own, so this returns "" for it rather
  ## than transitively peeling to the underlying `T`. (A named distinct alias is
  ## referenced by its alias name, which arrives here as an `nkIdent`.)
  if node == nil:
    return ""
  case node.kind
  of peelableModifierTyKinds:
    # Single wrapped child; peel it. Idempotent for nested wrappers like
    # `var ptr T` (nkVarTy(nkPtrTy(T))).
    if node.len >= 1:
      return peelToBaseTypeName(node[0])
    return ""
  of nkCommand:
    # `sink T` / `lent T` parse as nkCommand(nkIdent("sink"|"lent"), T).
    # The modifier head is normally a plain `nkIdent`/`nkSym`, but may arrive in
    # a module-qualified shape (e.g. `system.sink T` -> nkDotExpr head).
    #
    # Fast path (Gemini medium): for the common `nkIdent`/`nkSym` head, read the
    # identifier text directly instead of paying for `renderTree` +
    # `extractBaseName`. Fall back to the render path only for other head shapes
    # (notably the qualified `nkDotExpr` form), where `extractBaseName` degrades
    # the qualified spelling to the bare modifier name. Both paths apply
    # `nimIdentNormalize` and yield IDENTICAL results.
    # The `sink T` / `lent T` form the parser produces is EXACTLY
    # `nkCommand(nkIdent("sink"|"lent"), T)` — a 2-child node. Guard on the
    # expected child count (Gemini medium): only peel `node[1]` (the type
    # child) when the head is the sink/lent modifier AND the node has exactly
    # the expected 2-child shape. For the normal case `node[1] == node[^1]`, so
    # behavior is unchanged; an out-of-shape command (e.g. 3+ children) falls
    # through to the repr fallback below instead of peeling the wrong last child.
    if node.len == 2:
      let headNode = node[0]
      let head =
        case headNode.kind
        of nkIdent:
          nimIdentNormalize(headNode.ident.s)
        of nkSym:
          nimIdentNormalize(headNode.sym.name.s)
        else:
          nimIdentNormalize(extractBaseName(renderTree(headNode, {})))
      if head in ["sink", "lent"]:
        return peelToBaseTypeName(node[1])
    # Unknown command shape: fall back to repr normalization below.
  of nkBracketExpr:
    # Generic: peel to the head's base name.
    if node.len >= 1:
      return peelToBaseTypeName(node[0])
    return ""
  of nkIdent:
    return node.ident.s
  of nkSym:
    return node.sym.name.s
  of nkDotExpr:
    # `module.State` (or deeper) -> rightmost component is the base name.
    if node.len >= 2:
      return peelToBaseTypeName(node[^1])
    return ""
  of nkDistinctTy:
    # Do NOT peel through distinct: a bare inline distinct has no own name.
    return ""
  else:
    discard
  # Fallback: normalize the rendered repr (strips brackets/ref/ptr/module-qual).
  result = extractBaseName(renderTree(node, {}))

proc markerNameOf*(pragmaChild: PNode): string =
  ## Return the marker identifier name carried by one child of an `nkPragma`
  ## node, NORMALIZED per Nim's identifier rules (`nimIdentNormalize`), or ""
  ## when the shape is not an identifier-bearing pragma.
  ##
  ## Handles the bare form (`nkIdent`/`nkSym`, e.g. `transition`,
  ## `notATransition`) and the call/colon forms whose first child is the marker
  ## ident (`nkExprColonExpr` for `transitionError: "msg"`, `nkCall` for
  ## `transition(A, B)`).
  ##
  ## The result is style-normalized so a marker written in any valid Nim style
  ## (e.g. `not_a_transition`, `notatransition`) is recognized as the same
  ## marker. Pragma identifiers are style-insensitive in Nim, so this matches
  ## the compiler's own treatment. Callers in `classifyByPragma` compare against
  ## the normalized canonical spelling of each marker.
  var raw = ""
  if pragmaChild == nil:
    return ""
  case pragmaChild.kind
  of nkIdent:
    raw = pragmaChild.ident.s
  of nkSym:
    raw = pragmaChild.sym.name.s
  of nkExprColonExpr, nkCall, nkCommand:
    if pragmaChild.len >= 1:
      raw = extractIdent(pragmaChild[0])
  else:
    raw = ""
  if raw.len == 0:
    return ""
  result = nimIdentNormalize(raw)

proc classifyByPragma*(procDef: PNode): ProcClass =
  ## Classify a routine by its pragma markers.
  ##
  ## Reads the routine's `nkPragma` node at `pragmasPos` (`nkEmpty` means no
  ## pragmas) and walks its children via `markerNameOf`. Recognizes
  ## `transition` / `destructorTransition` (=> has-transition) and
  ## `notATransition` (=> has-not). All other pragmas (`discardable`, `raises`,
  ## `skipCfgAnalysis`, `transitionError`, `inline`, ...) are ignored.
  ##
  ## This is the key correctness fix over the old substring scanner: because it
  ## inspects each pragma child node individually, it detects markers embedded
  ## in a COMBINED block such as `{.discardable, raises: [], notATransition.}`.
  ##
  ## Returns `pcTransition` if a transition marker is present, else
  ## `pcNotATransition` if `notATransition` is present, else `pcUnmarked`.
  result = pcUnmarked
  if procDef == nil or procDef.len <= pragmasPos:
    return
  let pragmaNode = procDef[pragmasPos]
  if pragmaNode == nil or pragmaNode.kind == nkEmpty:
    return
  if pragmaNode.kind != nkPragma:
    return
  # `markerNameOf` returns the marker identifier NORMALIZED via
  # `nimIdentNormalize`, so the comparisons below use the canonical markers'
  # normalized spellings (first char preserved, rest lowercased, underscores
  # removed). This keeps marker SEMANTICS identical for canonical spellings
  # while also recognizing valid style variants (`not_a_transition`, etc.).
  const
    nTransition = nimIdentNormalize("transition")
    nDestructorTransition = nimIdentNormalize("destructorTransition")
    nNotATransition = nimIdentNormalize("notATransition")
  var hasTransition = false
  var hasNot = false
  for child in pragmaNode:
    case markerNameOf(child)
    of nTransition, nDestructorTransition:
      hasTransition = true
    of nNotATransition:
      hasNot = true
    else:
      discard
  if hasTransition:
    result = pcTransition
  elif hasNot:
    result = pcNotATransition
  else:
    result = pcUnmarked

proc typestateParamBases*(
    procDef: PNode, registeredBases: HashSet[string]
): seq[string] =
  ## Return the base type names of the routine's parameters whose peeled base
  ## type is a registered typestate base.
  ##
  ## Reads the routine's `nkFormalParams` node at `paramsPos`, iterates each
  ## `nkIdentDefs` (shape: `[name1, name2, ..., type, default]`, so the type is
  ## `idef[^2]`), peels the type via `peelToBaseTypeName`, and collects bases
  ## that are members of `registeredBases`. Grouped parameter names share a
  ## single type node and contribute one base per `nkIdentDefs`.
  ##
  ## Membership is tested style-insensitively per Nim's identifier rules
  ## (`nimIdentNormalize`): the first character is case-sensitive; the rest are
  ## case-insensitive and underscores are ignored. `registeredBases` MUST be
  ## supplied already normalized via `nimIdentNormalize` (the registration side
  ## in `cli.verify()` does this) so a state declared `MyState` matches a param
  ## typed `My_State`. The RETURNED base preserves the param's own (readable)
  ## spelling for use in user-facing findings.
  result = @[]
  if procDef == nil or procDef.len <= paramsPos:
    return
  let formalParams = procDef[paramsPos]
  if formalParams == nil or formalParams.kind != nkFormalParams:
    return
  for child in formalParams:
    if child.kind != nkIdentDefs:
      continue
    # A typed routine parameter is `[name1, ..., type, default]`, so the
    # minimum valid shape (single name) is `[name, type, default]` = 3 children.
    # Anything shorter has no extractable type at `^2`; skip it.
    if child.len < 3:
      continue
    let typeNode = child[^2]
    let base = peelToBaseTypeName(typeNode)
    if base.len > 0 and nimIdentNormalize(base) in registeredBases:
      result.add base

type ClassifiedProc* = object
  ## A routine definition classified by the AST verifier.
  ##
  ## Carries the best-effort routine name, the 1-indexed definition line and
  ## column (sourced from the `nkProcDef`/`nkFuncDef` node's `.info`), the
  ## pragma-marker classification, and the base type names of the routine's
  ## parameters that resolve to a registered typestate state. Only routines
  ## with at least one typestate-state parameter are produced by
  ## `classifyProcsInFile`; routines with no state parameter are irrelevant to
  ## the verifier and omitted.
  name*: string
  line*: int
  column*: int
  class*: ProcClass
  paramStateBases*: seq[string]

proc routineName(procDef: PNode): string =
  ## Best-effort routine name from `namePos` via `extractIdent`, which peels the
  ## exported (`nkPostfix`) and bare (`nkIdent`/`nkSym`) forms and renders
  ## backticked / operator names (`` proc `[]` ``, `` proc `==` ``,
  ## `` proc `[]`* ``) from their `nkAccQuoted` shape.
  ##
  ## Because `extractIdent` recurses through `nkPostfix` into `nkAccQuoted`, both
  ## the non-exported (`nkAccQuoted`) and EXPORTED
  ## (`nkPostfix[nkIdent("*"), nkAccQuoted]`) backticked forms yield the operator
  ## symbol; the prior cycle's top-level-only `nkAccQuoted` check missed the
  ## exported case.
  if procDef == nil or procDef.len <= namePos:
    return ""
  extractIdent(procDef[namePos])

proc classifyProcsInFile*(
    tree: PNode, registeredBases: HashSet[string]
): seq[ClassifiedProc] =
  ## Classify every top-level routine in a parsed file tree that has at least
  ## one parameter whose peeled base type is a registered typestate state.
  ##
  ## Collects routine defs via `collectRoutineDefs` (descending `nkStmtList`
  ## and `when`-branches, NOT routine bodies), computes each routine's
  ## typestate-state parameter bases via `typestateParamBases`, and — for
  ## routines with at least one such base — emits a `ClassifiedProc` carrying
  ## the routine name, 1-indexed def line/column (from the node's `.info`), the
  ## pragma classification (`classifyByPragma`), and the matched state bases.
  ##
  ## Routines with no typestate-state parameter are skipped: they are not
  ## subject to the transition-marking rule and would only add noise.
  result = @[]
  var defs: seq[PNode]
  collectRoutineDefs(tree, defs)
  for procDef in defs:
    let bases = typestateParamBases(procDef, registeredBases)
    if bases.len == 0:
      continue
    result.add ClassifiedProc(
      name: routineName(procDef),
      line: int(procDef.info.line),
      column: int(procDef.info.col) + 1,
      class: classifyByPragma(procDef),
      paramStateBases: bases,
    )

proc parseStringToPNode*(
    source: string, cache: IdentCache, config: ConfigRef, filename = "<string>"
): PNode =
  ## Parse an in-memory Nim source string into a raw `PNode`.
  ##
  ## Test hook mirroring `parsePNode`'s parse path (same `raisingErrorHandler`
  ## installation, same `openParser`/`parseAll`/`closeParser` sequence) but
  ## reading from a string instead of a file. Used by unit tests to exercise
  ## the classification helpers on small snippets. Raises `ParseError` on
  ## failure.
  var p: Parser
  let stream = llStreamOpen(source)
  if stream == nil:
    raise newParseError("Failed to open stream for: " & filename)
  p.lex.errorHandler = raisingErrorHandler
  openParser(p, AbsoluteFile(filename), stream, cache, config)
  try:
    result = parseAll(p)
  except ParseError:
    raise
  except Exception as e:
    raise newParseError("Parse error in " & filename & ": " & e.msg)
  finally:
    closeParser(p)

proc parseStringToPNode*(source: string, filename = "<string>"): PNode =
  ## Convenience overload of `parseStringToPNode` that constructs fresh
  ## compiler infrastructure per call. Prefer the cache/config form in loops.
  let cache = newIdentCache()
  let config = newConfigRef()
  config.notes = {}
  config.foreignPackageNotes = {}
  parseStringToPNode(source, cache, config, filename)

proc parsePNode*(path: string, cache: IdentCache, config: ConfigRef): PNode =
  ## Parse a Nim source file into a raw `PNode` using a shared compiler
  ## `IdentCache` and `ConfigRef`.
  ##
  ## Callers that process multiple files (e.g. `lintOpaqueStates`,
  ## `parseTypestatesAst`) should construct one cache/config pair and reuse
  ## them across every parse to avoid the per-file allocation cost of fresh
  ## compiler infrastructure. Raises `ParseError` on failure.
  if not fileExists(path):
    raise newParseError("File not found: " & path, path = path)

  let content = readFile(path)
  let absPath = AbsoluteFile(path.absolutePath)

  var p: Parser
  let stream = llStreamOpen(content)
  if stream == nil:
    raise newParseError("Failed to open stream for: " & path, path = path)

  # Install a raising error handler on the underlying lexer so syntax errors
  # surface as a catchable `ParseError` instead of going through the Nim
  # compiler's default `quit(1)` path inside `msgs.handleError`.
  #
  # Must be set BEFORE `openParser`: that proc calls `openLexer` (which does
  # NOT touch `errorHandler`, so the handler we set here survives) and then
  # `getTok(p)` to read the first token. If the very first token is
  # malformed, that read goes through `dispMessage` which would invoke the
  # default `quit(1)` path before any later assignment could take effect.
  # Setting the handler now ensures even a first-byte syntax error becomes
  # a catchable `ParseError`. (Mirrors the pattern in
  # `compiler/parser.parseString`, which assigns `p.lex.errorHandler`
  # before `openParser` for the same reason.)
  p.lex.errorHandler = raisingErrorHandler
  openParser(p, absPath, stream, cache, config)
  try:
    result = parseAll(p)
  except ParseError:
    raise
  except Exception as e:
    raise newParseError("Parse error in " & path & ": " & e.msg, path = path)
  finally:
    closeParser(p)

proc parsePNode*(path: string): PNode =
  ## Parse a Nim source file into a raw `PNode` using the compiler API.
  ##
  ## Convenience overload that creates a fresh `IdentCache` and `ConfigRef`
  ## per call. Prefer the 3-arg form when parsing multiple files in a loop.
  let cache = newIdentCache()
  let config = newConfigRef()

  # Configure for minimal output
  config.notes = {}
  config.foreignPackageNotes = {}

  parsePNode(path, cache, config)

proc parseFileWithAst*(
    path: string, cache: IdentCache, config: ConfigRef
): ParseResult =
  ## Parse a Nim file using the compiler's AST parser, reusing a shared
  ## `IdentCache` and `ConfigRef`. Raises `ParseError` if the file cannot be
  ## parsed.
  result = ParseResult()
  result.filesChecked = 1

  let ast = parsePNode(path, cache, config)
  walkAst(ast, result.typestates)

proc parseFileWithAst*(path: string): ParseResult =
  ## Parse a Nim file using the compiler's AST parser.
  ##
  ## Convenience overload that creates fresh compiler infrastructure per
  ## call. Prefer the 3-arg form when parsing multiple files in a loop.
  ##
  ## Raises ParseError if the file cannot be parsed.
  result = ParseResult()
  result.filesChecked = 1

  let ast = parsePNode(path)
  walkAst(ast, result.typestates)

proc parseTypestatesAst*(paths: seq[string]): ParseResult =
  ## Parse all Nim files in the given paths for typestates.
  ##
  ## Creates one `IdentCache` and one `ConfigRef` and reuses them across
  ## every file, avoiding per-file compiler-infrastructure allocation.
  ##
  ## Per-file `ParseError`s are accumulated into `result.failures` rather
  ## than aborting the entire batch — `typestates verify --format=github
  ## src/` should produce annotations for every problem the user has, not
  ## just the first parse error. Successfully parsed files contribute
  ## their typestates to `result.typestates` and `filesChecked`. Callers
  ## (e.g. `verify()` and `lintOpaqueStates`) inspect `failures` to emit
  ## one `fcParseError` Finding per failed path.
  result = ParseResult()

  let cache = newIdentCache()
  let config = newConfigRef()
  config.notes = {}
  config.foreignPackageNotes = {}

  for path in paths:
    if path.endsWith(".nim"):
      try:
        let fileResult = parseFileWithAst(path, cache, config)
        result.typestates.add fileResult.typestates
        result.filesChecked += fileResult.filesChecked
      except ParseError as e:
        recordFailure(result, path, e)
    elif dirExists(path):
      for file in walkDirRec(path):
        if file.endsWith(".nim"):
          try:
            let fileResult = parseFileWithAst(file, cache, config)
            result.typestates.add fileResult.typestates
            result.filesChecked += fileResult.filesChecked
          except ParseError as e:
            recordFailure(result, file, e)

type ParsedProject* = object
  ## Tier-B parse-sharing result: a `ParseResult` (typestates + per-file
  ## failures + file count) PLUS the raw parsed `PNode` tree for every file
  ## that parsed successfully, keyed by the path AS ENCOUNTERED (the literal
  ## `.nim` argument for explicit files; the `walkDirRec` path for directory
  ## entries). Keying by the as-encountered path lets downstream `Finding`s
  ## carry the same path string the user supplied, preserving v0.9.3 output.
  ##
  ## A single parse per file feeds BOTH typestate extraction (Pass 1) and proc
  ## classification (Pass 2). `PNode` consumption is read-only across all
  ## consumers (see the "PNode immutability (Tier-B note)" comment above the
  ## classification helpers), so sharing one parse is sound.
  ##
  ## Files that failed to parse appear only in `parse.failures` — they have no
  ## entry in `nodes`, so a downstream classification pass naturally skips them
  ## without re-parsing or double-reporting the parse error.
  parse*: ParseResult
  nodes*: OrderedTable[string, PNode]
    ## Keyed by the as-encountered path. An `OrderedTable` (not a plain `Table`)
    ## so Pass-2 iteration follows insertion order — the order `paths` are
    ## processed — making finding report order deterministic across runs for the
    ## same inputs (a plain `Table` iterates in hash order).

proc parseTypestatesAstWithNodes*(paths: seq[string]): ParsedProject =
  ## Parse every `.nim` file under `paths` EXACTLY ONCE and return both the
  ## extracted typestates (Pass-1 view) and the raw `PNode` trees (for Pass-2
  ## proc classification), keyed by absolute path.
  ##
  ## Tier-B unification of `parseTypestatesAst`: instead of walking each file
  ## for typestates and discarding the tree (which forced `verify()` to re-read
  ## and re-scan each file in a second pass), this retains the parsed tree so a
  ## single parse serves both passes. Per-file `ParseError`s are accumulated
  ## into `result.parse.failures` (one per failed path) rather than aborting
  ## the batch — identical failure semantics to `parseTypestatesAst`.
  ##
  ## `filesChecked` counts only successfully-parsed files (matching
  ## `parseTypestatesAst`). A failed file contributes a `failures` entry, no
  ## `nodes` entry, and no `filesChecked` increment.
  result = ParsedProject(parse: ParseResult(), nodes: initOrderedTable[string, PNode]())

  let cache = newIdentCache()
  let config = newConfigRef()
  config.notes = {}
  config.foreignPackageNotes = {}

  proc handleFile(project: var ParsedProject, file: string) =
    try:
      let tree = parsePNode(file, cache, config)
      walkAst(tree, project.parse.typestates)
      project.parse.filesChecked += 1
      project.nodes[file] = tree
    except ParseError as e:
      recordFailure(project.parse, file, e)
    except CatchableError as e:
      # Gemini round-3 HIGH: `parsePNode` -> `readFile` can raise
      # `IOError`/`OSError` (permission denied, path is dir, etc.). Pre-fix
      # only `ParseError` was caught, so a single unreadable file would
      # abort the entire batch instead of producing a structured failure.
      # Wrap as a `ParseError` so the rest of the pipeline (formatters,
      # JSON envelope, GitHub annotations) handles it identically to a
      # syntax error.
      let pe = newException(ParseError, "I/O error reading " & file & ": " & e.msg)
      pe.path = file
      recordFailure(project.parse, file, pe)

  for path in paths:
    if path.endsWith(".nim"):
      handleFile(result, path)
    elif dirExists(path):
      for file in walkDirRec(path):
        if file.endsWith(".nim"):
          handleFile(result, file)
