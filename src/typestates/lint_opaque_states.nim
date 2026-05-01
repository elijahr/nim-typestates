## Opt-in CLI lint that flags raw distinct casts to non-initial opaque states
## outside `{.transition.}` proc bodies.
##
## Activated when a typestate has `opaqueStates = true`. Warnings only;
## never errors. See docs/guide/cast-protection.md.
##
## Algorithm:
##
## 1. Build `opaqueNonInitial` table from typestates with `opaqueStates = true`.
##    Skip initial states; emit a one-time configuration warning for any
##    opaque-flagged typestate with no initial states declared.
## 2. If the table is empty, return immediately (fast path).
## 3. For each path, parse the source file via the compiler API and walk the
##    AST tracking an `inTransition` flag. Routine definitions are separate
##    scopes: a routine carrying `{.transition.}` lints its body with
##    `inTransition = 1`; any other routine def (including nested unmarked
##    procs, templates, and macros) lints its body with `inTransition = 0`.
##    `nkLambda` / `nkDo` are anonymous scopes that inherit the surrounding
##    flag.
## 4. Calls (`nkCall`/`nkCommand`) where the callee is an `nkIdent` or
##    `nkDotExpr` referencing a non-initial opaque state, with
##    `inTransition == 0`, emit a warning.

import std/[os, sets, strformat, strutils, tables]

import compiler/[ast, idents, options as compiler_options]

import ./ast_parser # re-uses ParseResult, ParseError, parsePNode
import ./findings

type
  OpaqueInfo = object
    typestate: string

  LintCtx = object
    opaqueNonInitial: Table[string, OpaqueInfo]
    inTransition: int
    findings: seq[Finding]
    path: string

const RoutineDefKinds =
  {nkProcDef, nkFuncDef, nkMethodDef, nkConverterDef, nkIteratorDef}

proc hasTransitionPragma(routine: PNode): bool =
  ## Detect `{.transition.}`, `{.async, transition.}`, or
  ## `{.transition: xyz.}` on a routine definition node.
  if routine.len <= pragmasPos:
    return false
  let prag = routine[pragmasPos]
  if prag.kind != nkPragma:
    return false
  for child in prag:
    var name = ""
    case child.kind
    of nkIdent:
      name = child.ident.s
    of nkSym:
      name = child.sym.name.s
    of nkExprColonExpr, nkCall:
      if child.len >= 1:
        case child[0].kind
        of nkIdent:
          name = child[0].ident.s
        of nkSym:
          name = child[0].sym.name.s
        else:
          discard
    else:
      discard
    if name == "transition":
      return true
  false

proc inspectCall(n: PNode, ctx: var LintCtx) =
  ## Emit a warning if `n` is a call to a non-initial opaque state outside
  ## a `{.transition.}` body. Caller handles recursion into children.
  if ctx.inTransition > 0:
    return
  if n.len < 1:
    return
  let callee = n[0]
  var name = ""
  case callee.kind
  of nkIdent:
    name = callee.ident.s
  of nkSym:
    name = callee.sym.name.s
  of nkDotExpr:
    if callee.len >= 2:
      case callee[1].kind
      of nkIdent:
        name = callee[1].ident.s
      of nkSym:
        name = callee[1].sym.name.s
      else:
        discard
  else:
    discard
  if name.len == 0:
    return
  if name notin ctx.opaqueNonInitial:
    return
  let info = ctx.opaqueNonInitial[name]
  ctx.findings.add mkWarning(
    fcOpaqueStateBypass,
    ctx.path,
    int(n.info.line),
    fmt"bypass of opaque state '{name}' (typestate '{info.typestate}') outside {{.transition.}} proc",
  )

proc walk(n: PNode, ctx: var LintCtx) =
  if n == nil:
    return

  # Routine definitions are SEPARATE scopes from their enclosing routine.
  # A nested `proc inner()` declared inside a `{.transition.}` body does
  # not inherit the outer's transition status — its body must be linted
  # afresh. Templates and macros likewise carry their own scope.
  #
  # nkLambda/nkDo are anonymous scopes that DO inherit (they're part of
  # the surrounding expression, not a separate definition site).
  if n.kind in RoutineDefKinds + {nkTemplateDef, nkMacroDef}:
    let savedInTransition = ctx.inTransition
    ctx.inTransition =
      if n.kind in RoutineDefKinds and hasTransitionPragma(n): 1 else: 0
    for child in n:
      walk(child, ctx)
    ctx.inTransition = savedInTransition
    return

  if n.kind in {nkCall, nkCommand}:
    inspectCall(n, ctx)
  for child in n:
    walk(child, ctx)

proc lintOpaqueStates*(parseResult: ParseResult, paths: seq[string]): seq[Finding] =
  ## Returns structured `Finding` records. Empty seq when no typestate has
  ## opted in. Configuration warnings (no path/line) are prepended; per-file
  ## `ParseError` is converted into a `fcParseError` Finding so a malformed
  ## file does not abort the lint pipeline.
  result = @[]
  var ctx = LintCtx()

  # Step 0: build the opaque table; emit config warnings for opaque-flagged
  # typestates with no declared initial states.
  for pt in parseResult.typestates:
    if not pt.opaqueStates:
      continue
    if pt.initialStates.len == 0:
      result.add mkWarning(
        fcOpaqueStatesNoInitials,
        "",
        0,
        fmt"opaqueStates = true on typestate '{pt.name}' but no initial states declared; lint disabled for this typestate",
      )
      continue
    for state in pt.states:
      if state notin pt.initialStates:
        ctx.opaqueNonInitial[state] = OpaqueInfo(typestate: pt.name)

  # Fast path: nothing to lint. Return any config warnings already collected.
  if ctx.opaqueNonInitial.len == 0:
    return result

  # Step 1: walk every .nim source file under the verified paths.
  # Share one IdentCache and ConfigRef across every parsePNode call so we
  # don't pay the per-file compiler-infrastructure allocation cost.
  let cache = newIdentCache()
  let config = newConfigRef()
  config.notes = {}
  config.foreignPackageNotes = {}

  # Track visited absolute paths so overlapping inputs (e.g. `["src",
  # "src/main.nim"]`) don't double-process and double-warn.
  var visited = initHashSet[string]()
  proc shouldProcess(file: string): bool =
    let abs = absolutePath(file)
    if abs in visited:
      return false
    visited.incl(abs)
    return true

  for path in paths:
    if path.endsWith(".nim"):
      if not shouldProcess(path):
        continue
      ctx.path = path
      ctx.inTransition = 0
      try:
        let ast = parsePNode(path, cache, config)
        walk(ast, ctx)
      except ParseError as e:
        result.add mkError(fcParseError, path, 0, e.msg)
        continue
    elif dirExists(path):
      for file in walkDirRec(path):
        if file.endsWith(".nim"):
          if not shouldProcess(file):
            continue
          ctx.path = file
          ctx.inTransition = 0
          try:
            let ast = parsePNode(file, cache, config)
            walk(ast, ctx)
          except ParseError as e:
            result.add mkError(fcParseError, file, 0, e.msg)
            continue

  result.add ctx.findings
