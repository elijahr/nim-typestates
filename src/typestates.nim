## Compile-time state machine verification for Nim.
##
## This library enforces state machine protocols at compile time through
## Nim's type system. Programs that compile have been verified to contain
## no invalid state transitions.
##
## This approach is known as *correctness by construction*: invalid states
## become unrepresentable rather than checked at runtime.
##
## **Exports:**
##
## - `typestate` macro - Declare states and transitions
## - `{.transition.}` pragma - Mark and validate transition procs
## - `{.notATransition.}` pragma - Mark non-transition procs

import std/macros
import typestates/[types, parser, registry, pragmas, codegen, constraints]

export types, pragmas, constraints

proc needsConstraintInference(name, body: NimNode): tuple[needed: bool, stateIdent: NimNode] =
  ## Check if the typestate needs constraint inference.
  ##
  ## Returns true if:
  ## - name has unconstrained generic params (like `Base[N]` not `Base[N: static int]`)
  ## - body has a states section with generic states (like `StateA[N]`)
  ##
  ## Also returns the first generic state ident for use in inference.
  result = (false, newEmptyNode())

  # Extract type params from name
  var typeParams: seq[NimNode] = @[]
  if name.kind == nnkBracketExpr:
    for i in 1..<name.len:
      typeParams.add name[i]

  if typeParams.len == 0:
    return

  # Check if any params are unconstrained
  var hasUnconstrained = false
  for p in typeParams:
    if p.kind == nnkIdent:
      hasUnconstrained = true
      break

  if not hasUnconstrained:
    return

  # Find states section and check for generic states
  for child in body:
    if child.kind in {nnkCall, nnkCommand}:
      if child[0].kind == nnkIdent and child[0].strVal == "states":
        # Found states section - check for generic states
        for i in 1..<child.len:
          let stateNode = child[i]
          if stateNode.kind == nnkBracketExpr:
            # Found a generic state - return it for inference
            return (true, stateNode[0].copyNimTree)
          elif stateNode.kind == nnkStmtList:
            # Multiline block
            for sub in stateNode:
              if sub.kind == nnkBracketExpr:
                return (true, sub[0].copyNimTree)

macro typestateImpl*(
  name: untyped,
  body: untyped,
  inferredConstraints: static[seq[tuple[name: string, kind: string, constraint: string]]]
): untyped =
  ## Internal implementation that receives inferred constraints.
  ##
  ## This macro is called after constraint inference to generate the typestate
  ## with properly constrained generic parameters.

  # Augment the name node with inferred constraints
  var augmentedName = name.copyNimTree

  if name.kind == nnkBracketExpr and inferredConstraints.len > 0:
    # Rebuild the bracket expr with constrained params
    augmentedName = nnkBracketExpr.newTree(name[0].copyNimTree)
    for i in 1..<name.len:
      let p = name[i]
      if p.kind == nnkIdent:
        # Unconstrained - look for inferred constraint
        let paramName = p.strVal
        var found = false
        for c in inferredConstraints:
          if c.name == paramName:
            found = true
            case c.kind
            of "static":
              augmentedName.add nnkExprColonExpr.newTree(
                ident(paramName),
                nnkCommand.newTree(ident("static"), ident(c.constraint))
              )
            of "typeclass":
              augmentedName.add nnkExprColonExpr.newTree(
                ident(paramName),
                ident(c.constraint)
              )
            else:
              augmentedName.add p.copyNimTree
            break
        if not found:
          augmentedName.add p.copyNimTree
      else:
        # Already constrained
        augmentedName.add p.copyNimTree

  # Parse with augmented name
  let graph = parseTypestateBody(augmentedName, body)

  # Register for later validation
  registerTypestate(graph)

  # Register states for external checking
  var stateNames: seq[string] = @[]
  for stateName in graph.states.keys:
    stateNames.add stateName
  registerSealedStates(graph.declaredInModule, stateNames)

  # Check for codegen bug vulnerability
  when (NimMajor, NimMinor, NimPatch) < (2, 2, 8):
    if hasHookCodegenBugConditions(graph):
      error(
        "Typestate '" & graph.name & "' uses `static` generic parameters with " &
        "`consumeOnTransition = true`, which triggers a codegen bug in Nim < 2.2.8 " &
        "affecting ARC, ORC, AtomicARC, and any memory manager that uses hooks.\n" &
        "Options:\n" &
        "  1. Use `--mm:refc` instead of ARC/ORC\n" &
        "  2. Make '" & graph.name & "' inherit from RootObj and add `inheritsFromRootObj = true`\n" &
        "  3. Upgrade to Nim >= 2.2.8 (when released)\n" &
        "  4. Add `consumeOnTransition = false` to disable =copy hooks\n" &
        "See: https://github.com/nim-lang/Nim/issues/25341",
        augmentedName
      )

  # Generate helper types
  result = generateAll(graph)

macro typestate*(name: untyped, body: untyped): untyped =
  ## Define a typestate with states and valid transitions.
  ##
  ## The typestate block declares:
  ##
  ## - **states**: The distinct types that represent each state
  ## - **transitions**: Which state changes are allowed
  ##
  ## Basic syntax:
  ##
  ## ```nim
  ## typestate File:
  ##   states Closed, Open, Errored
  ##   transitions:
  ##     Closed -> Open | Errored    # Branching
  ##     Open -> Closed
  ##     * -> Closed                 # Wildcard
  ## ```
  ##
  ## Generic typestates with constraint inference:
  ##
  ## ```nim
  ## type
  ##   Base[N: static int] = object
  ##   StateA[N: static int] = distinct Base[N]
  ##   StateB[N: static int] = distinct Base[N]
  ##
  ## # N's constraint is automatically inferred from StateA/StateB
  ## typestate Base[N]:
  ##   states StateA[N], StateB[N]
  ##   transitions:
  ##     StateA -> StateB
  ## ```
  ##
  ## What it generates:
  ##
  ## - `FileState` enum with `fsClosed`, `fsOpen`, `fsErrored`
  ## - `FileStates` union type for generic procs
  ## - `state()` procs for runtime inspection
  ##
  ## Transition syntax:
  ##
  ## - `A -> B` - Simple transition
  ## - `A -> B | C` - Branching (can go to B or C)
  ## - `* -> X` - Wildcard (any state can go to X)
  ##
  ## See also: `{.transition.}` pragma for implementing transitions
  ##
  ## :param name: The base type name (must match your type definition)
  ## :param body: The states and transitions declarations
  ## :returns: Generated helper types (enum, union, state procs)

  # Check if constraint inference is needed
  let (needsInference, stateIdent) = needsConstraintInference(name, body)

  if needsInference:
    # Two-phase approach: generate call to typestateImpl with inferred constraints
    # The typed macro inferConstraintsTyped runs first (in semantic phase),
    # then typestateImpl receives the inferred constraints as static data
    #
    # We use nnkCall.newTree instead of `quote do:` because the name and body
    # contain generic params (like N) that aren't in scope during quote expansion.
    # Building the call manually with copyNimTree preserves them as untyped AST.
    result = nnkCall.newTree(
      bindSym("typestateImpl"),
      name.copyNimTree,
      body.copyNimTree,
      nnkCall.newTree(
        bindSym("inferConstraintsTyped"),
        stateIdent
      )
    )
  else:
    # No inference needed - proceed with direct implementation
    # Parse the typestate body
    let graph = parseTypestateBody(name, body)

    # Register for later validation
    registerTypestate(graph)

    # Register states for external checking
    var stateNames: seq[string] = @[]
    for stateName in graph.states.keys:
      stateNames.add stateName
    registerSealedStates(graph.declaredInModule, stateNames)

    # Check for codegen bug vulnerability (fixed in Nim >= 2.2.8)
    # Affects: ORC, ARC, AtomicARC, and any memory manager using hooks
    # See: https://github.com/nim-lang/Nim/issues/25341
    when (NimMajor, NimMinor, NimPatch) < (2, 2, 8):
      if hasHookCodegenBugConditions(graph):
        error(
          "Typestate '" & graph.name & "' uses `static` generic parameters with " &
          "`consumeOnTransition = true`, which triggers a codegen bug in Nim < 2.2.8 " &
          "affecting ARC, ORC, AtomicARC, and any memory manager that uses hooks.\n" &
          "Options:\n" &
          "  1. Use `--mm:refc` instead of ARC/ORC\n" &
          "  2. Make '" & graph.name & "' inherit from RootObj and add `inheritsFromRootObj = true`\n" &
          "  3. Upgrade to Nim >= 2.2.8 (when released)\n" &
          "  4. Add `consumeOnTransition = false` to disable =copy hooks\n" &
          "See: https://github.com/nim-lang/Nim/issues/25341",
          name
        )

    # Generate helper types
    result = generateAll(graph)
