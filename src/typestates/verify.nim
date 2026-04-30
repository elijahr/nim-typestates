## Verification utilities for typestate checking.
##
## Provides:
##
## - Compile-time proc registration for validation
## - `verifyTypestates()` macro for in-module verification
## - CLI tool support for full-project verification

import std/[macros, options, os, strformat, strutils, tables]
import types, registry

type
  ProcKind* = enum
    ## Classification of procs operating on state types.
    pkTransition ## Marked with `{.transition.}`
    pkNotATransition ## Marked with `{.notATransition.}`
    pkUnmarked ## No pragma specified

  RegisteredProc* = object
    ## Information about a proc registered for verification.
    ##
    ## :var name: The proc name
    ## :var sourceState: The first parameter's state type
    ## :var destStates: Return type state(s)
    ## :var kind: How the proc is marked
    ## :var declaredAt: Source location
    ## :var modulePath: Module where declared
    ## :var firstParamType: AST of the first parameter's type (preserves
    ##   modifiers like `sink`, `var`, `ref`, `ptr` for F5 decoy emission)
    ## :var extraParams: Trailing formal-parameter IdentDefs (params 2..N)
    ##   captured verbatim so F5 decoys reproduce the full signature,
    ##   matching overload resolution at call sites with extra args
    name*: string
    sourceState*: string
    destStates*: seq[string]
    kind*: ProcKind
    declaredAt*: LineInfo
    modulePath*: string
    firstParamType*: NimNode
    extraParams*: seq[NimNode]

var registeredProcs* {.compileTime.}: seq[RegisteredProc]
  ## Compile-time list of all procs registered for verification.

proc registerProc*(info: RegisteredProc) {.compileTime.} =
  ## Register a proc for later verification.
  ##
  ## :param info: The proc information to register
  registeredProcs.add info

macro verifyTypestates*(): untyped =
  ## Verify all registered typestates and procs.
  ##
  ## Call at the end of a module to check:
  ##
  ## - All transitions are valid
  ## - All procs on state types are properly marked (if strictTransitions)
  ## - No external transitions on sealed typestates
  ##
  ## Example:
  ##
  ## ```nim
  ## import typestates
  ##
  ## typestate File:
  ##   states Closed, Open
  ##   transitions:
  ##     Closed -> Open
  ##
  ## proc open(f: Closed): Open {.transition.} = ...
  ##
  ## verifyTypestates()  # Validates everything above
  ## ```
  ##
  ## :returns: Empty statement list (validation is compile-time only)
  ## :raises: Compile-time error if verification fails

  result = newStmtList()

  # Check each registered proc
  for procInfo in registeredProcs:
    if procInfo.kind == pkUnmarked:
      # Find the typestate for this state
      let graphOpt = findTypestateForState(procInfo.sourceState)
      if graphOpt.isSome:
        let graph = graphOpt.get

        # Check strictTransitions
        if graph.strictTransitions:
          error(
            fmt"""Unmarked proc '{procInfo.name}' operates on state '{procInfo.sourceState}'.
  Typestate '{graph.name}' has strictTransitions = true.
  Add {{.transition.}} or {{.notATransition.}} pragma.
  Declared at: {procInfo.declaredAt}"""
          )

        # Check for external procs
        if procInfo.modulePath != graph.declaredInModule:
          error(
            fmt"""Unmarked proc '{procInfo.name}' on typestate '{graph.name}' from external module.
  External modules must use {{.notATransition.}} for procs on typestate states.
  Declared at: {procInfo.declaredAt}"""
          )

  # F5: emit state-aware error decoy procs for transitions in this module.
  #
  # For each (procName, typestate) pair in `registeredProcs`, build the set
  # of source states already covered by a real `{.transition.}` overload.
  # For every OTHER state in that typestate, emit a `{.error: "...".}` decoy
  # so calling the proc on the wrong source state fires a tailored compile
  # error instead of the generic "type mismatch" diagnostic.
  #
  # v0.5 scope (intentional skips):
  #   - Generic typestates (`graph.typeParams.len > 0`): codegen extension
  #     deferred to v0.6 (see CHANGELOG).
  #   - Branching-return procs (`destStates.len > 1`): deferred to v0.6.
  #   - Union-source procs (registered with `sourceState == ""`): the proc
  #     covers multiple source states; treat each covered state as a real
  #     overload but do not emit a decoy keyed off the union.
  #   - External-module procs: cannot exist for `{.transition.}` (validated
  #     in pragmas.nim), but defensively skipped here too.
  type
    TransitionKey = tuple[name: string, typestateName: string]
    TransitionInfo = object
      name: string
      typestate: TypestateGraph
      coveredSources: seq[string]
      destStates: seq[string]
      modulePath: string
      firstParamType: NimNode # AST of the first param type (any source state)
      extraParams: seq[NimNode] # Trailing IdentDefs from the registered overload
      anySkipped: bool # any overload of this name was generic / branching / union

  var groups: Table[TransitionKey, TransitionInfo]

  for procInfo in registeredProcs:
    if procInfo.kind != pkTransition:
      continue
    if procInfo.sourceState.len == 0:
      # Union-source proc: skip the entire group (v0.5 deferral). We still
      # want to mark this group as "skipped" so we don't emit half-decoys
      # for a name whose union overload covers multiple states.
      continue
    let graphOpt = findTypestateForState(procInfo.sourceState)
    if graphOpt.isNone:
      continue
    let graph = graphOpt.get
    if procInfo.modulePath != graph.declaredInModule:
      continue
    let key: TransitionKey = (name: procInfo.name, typestateName: graph.name)
    if key notin groups:
      groups[key] = TransitionInfo(
        name: procInfo.name,
        typestate: graph,
        coveredSources: @[],
        destStates: procInfo.destStates,
        modulePath: procInfo.modulePath,
        firstParamType: procInfo.firstParamType,
        extraParams: procInfo.extraParams,
        anySkipped: false,
      )
    if procInfo.sourceState notin groups[key].coveredSources:
      groups[key].coveredSources.add procInfo.sourceState
    # If overloads disagree on extra params or destination, the decoy can't
    # represent both signatures; mark the group skipped to avoid a partial
    # decoy that wouldn't catch every misuse cleanly.
    if procInfo.extraParams.len != groups[key].extraParams.len:
      groups[key].anySkipped = true
    if procInfo.destStates.len != 1:
      groups[key].anySkipped = true

  # Re-scan registeredProcs to flag groups with a union-source overload as
  # skipped. We can't tell from `(name, typestateName)` alone in the first
  # pass, because a union-source proc has `sourceState == ""` and we never
  # added it to `coveredSources` — but we still need to detect that some
  # overload of this name takes a union.
  for procInfo in registeredProcs:
    if procInfo.kind != pkTransition:
      continue
    if procInfo.sourceState.len != 0:
      continue
    # Union proc: find which typestate(s) it might belong to. We don't have
    # that info reliably, so treat all groups with the same name as skipped.
    for key in groups.keys:
      if key.name == procInfo.name:
        groups[key].anySkipped = true

  # Helper: produce a new first-param type AST that preserves the original
  # modifier shape (sink T, var T, ref T, ptr T, plain T) but swaps the
  # leaf type ident for the new state ident.
  proc replaceLeafState(node: NimNode, newIdent: NimNode): NimNode =
    case node.kind
    of nnkIdent, nnkSym:
      result = newIdent
    of nnkCommand:
      if node.len == 2 and node[0].kind == nnkIdent and node[0].strVal == "sink":
        result = nnkCommand.newTree(node[0].copyNimTree, newIdent)
      else:
        result = newIdent
    of nnkVarTy:
      result = nnkVarTy.newTree(newIdent)
    of nnkRefTy:
      result = nnkRefTy.newTree(newIdent)
    of nnkPtrTy:
      result = nnkPtrTy.newTree(newIdent)
    else:
      result = newIdent

  for key, info in groups:
    if info.anySkipped:
      continue
    if info.typestate.typeParams.len > 0:
      continue # v0.6: generic typestates deferred
    if info.destStates.len != 1:
      continue # branching-return deferred

    for stateName, state in info.typestate.states:
      let stateBase = extractBaseName(stateName)
      if stateBase in info.coveredSources:
        continue
      # Build the tailored error message naming the proc, the wrong state,
      # the expected (one of) source state(s), and the location of the real
      # transition for navigability.
      let expectedList = info.coveredSources.join("' or '")
      let errorMsg =
        "Cannot call '" & info.name & "' on a value in state '" & stateBase &
        "'. Expected '" & expectedList & "'. (Defined at " &
        extractFilename(info.modulePath) & ")"

      let stateIdent = ident(stateBase)
      let procIdent = ident(info.name)
      # The decoy is exported (`*`) so it is visible at call sites in
      # downstream modules. Transitions are typically exported.
      let exportedName = nnkPostfix.newTree(ident("*"), procIdent)
      # Decoys carry only {.error.} — other pragmas like {.async.} aren't
      # propagated because {.error.} short-circuits before they would matter.
      let errorPragma =
        nnkPragma.newTree(nnkExprColonExpr.newTree(ident("error"), newLit(errorMsg)))
      # Build formal params: `auto` return (never reached — `{.error.}`
      # short-circuits) + first param with the wrong-state type + the same
      # trailing parameters as the real overload so `proc close(a, reason)`
      # generates `proc close(p: sink Frozen, reason: string)` decoys that
      # match the user's call shape.
      var formalParams = nnkFormalParams.newNimNode()
      formalParams.add ident("auto")
      formalParams.add nnkIdentDefs.newTree(
        ident("p"), replaceLeafState(info.firstParamType, stateIdent), newEmptyNode()
      )
      for extra in info.extraParams:
        formalParams.add extra.copyNimTree
      let decoyProc = nnkProcDef.newTree(
        exportedName,
        newEmptyNode(),
        newEmptyNode(),
        formalParams,
        errorPragma,
        newEmptyNode(),
        nnkStmtList.newTree(nnkDiscardStmt.newTree(newEmptyNode())),
      )
      result.add decoyProc

  # Return empty - just for compile-time checking
  result.add newCommentStmtNode("typestates verified")
