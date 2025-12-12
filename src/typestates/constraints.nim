## Constraint inference for generic typestate parameters.
##
## This module provides typed macros that can introspect state type definitions
## to extract generic parameter constraints at compile time.
##
## The key insight is that a typed macro receiving `typedesc` parameters can
## use `getType()` and `getImpl()` to discover constraints like `static int`.
##
## **Limitation**: Type class constraints (e.g., `T: SomeNumber`) are not
## directly accessible via Nim's macro introspection. Only `static` constraints
## can be reliably detected. Users must still manually specify type class
## constraints in their typestate declarations.

import std/[macros, tables]

type
  ConstraintKind* = enum
    ckNone        ## No constraint (plain type variable)
    ckStatic      ## static constraint (e.g., static int)
    ckTypeClass   ## Type class constraint (e.g., SomeNumber)

  InferredConstraint* = object
    ## Represents an inferred constraint for a generic parameter
    paramName*: string
    kind*: ConstraintKind
    constraint*: NimNode  ## The constraint AST

proc extractConstraintsFromType*(typeSym: NimNode): seq[InferredConstraint] =
  ## Extract generic constraints from a type symbol.
  ##
  ## Uses getImpl() to get the TypeDef AST, then inspects GenericParams
  ## to discover constraints on each parameter.
  result = @[]

  if typeSym.kind != nnkSym:
    return

  let impl = typeSym.getImpl()
  if impl.kind != nnkTypeDef:
    return

  let genericParams = impl[1]
  if genericParams.kind != nnkGenericParams:
    return

  for paramNode in genericParams:
    if paramNode.kind == nnkSym:
      let paramName = paramNode.strVal
      let paramType = paramNode.getType()

      var constraint: InferredConstraint
      constraint.paramName = paramName

      if paramType.kind == nnkBracketExpr:
        # Has a constraint - check what kind
        let constraintName = if paramType[0].kind == nnkSym: paramType[0].strVal else: ""
        if constraintName == "static":
          constraint.kind = ckStatic
          # Extract the inner type if present (e.g., `int` from `static[int]`)
          if paramType.len > 1:
            constraint.constraint = paramType[1].copyNimTree
          else:
            # Just `static` without inner type means static int
            constraint.constraint = ident("int")
        else:
          # Type class constraint like SomeNumber
          constraint.kind = ckTypeClass
          constraint.constraint = paramType[0].copyNimTree
      else:
        # No constraint - plain type variable
        constraint.kind = ckNone
        constraint.constraint = newEmptyNode()

      result.add constraint

proc buildConstraintNode*(c: InferredConstraint): NimNode =
  ## Build a NimNode representing a generic parameter with its constraint.
  ##
  ## Examples:
  ##   ckNone -> `N`
  ##   ckStatic -> `N: static int`
  ##   ckTypeClass -> `T: SomeNumber`
  case c.kind
  of ckNone:
    result = ident(c.paramName)
  of ckStatic:
    # Build: N: static int
    result = nnkExprColonExpr.newTree(
      ident(c.paramName),
      nnkCommand.newTree(
        ident("static"),
        c.constraint.copyNimTree
      )
    )
  of ckTypeClass:
    # Build: T: SomeNumber
    result = nnkExprColonExpr.newTree(
      ident(c.paramName),
      c.constraint.copyNimTree
    )

proc constraintsMatch*(a, b: InferredConstraint): bool =
  ## Check if two constraints are compatible.
  if a.kind != b.kind:
    return false
  if a.kind == ckNone:
    return true
  # For static and type class, compare the constraint AST repr
  return a.constraint.repr == b.constraint.repr

macro inferConstraintsFromState*(T: typedesc): untyped =
  ## Typed macro that extracts generic constraints from a single state type.
  ##
  ## This macro runs in a typed context, allowing us to use getType/getImpl
  ## to introspect the actual type definition.
  ##
  ## Returns a tuple literal with constraint information that can be
  ## processed at compile time.

  let typeNode = T.getType()

  # typeNode is BracketExpr[Sym "typedesc", Sym "ActualType"]
  if typeNode.kind != nnkBracketExpr or typeNode.len < 2:
    # Non-generic type, return empty
    return nnkTupleConstr.newTree()

  let typeSym = typeNode[1]
  if typeSym.kind != nnkSym:
    return nnkTupleConstr.newTree()

  let constraints = extractConstraintsFromType(typeSym)

  # Build result as a tuple of (name, kind, constraintRepr) tuples
  result = nnkTupleConstr.newTree()
  for c in constraints:
    let kindStr = case c.kind
      of ckNone: "none"
      of ckStatic: "static"
      of ckTypeClass: "typeclass"

    let constraintRepr = if c.constraint.kind != nnkEmpty:
      c.constraint.repr
    else:
      ""

    result.add nnkTupleConstr.newTree(
      newLit(c.paramName),
      newLit(kindStr),
      newLit(constraintRepr)
    )

proc parseInferredConstraints*(tupleData: NimNode): seq[InferredConstraint] =
  ## Parse the tuple data returned by inferConstraintsFromState back into
  ## InferredConstraint objects.
  ##
  ## This runs at macro-time to process the results of the typed inference.
  result = @[]

  if tupleData.kind != nnkTupleConstr:
    return

  for item in tupleData:
    if item.kind != nnkTupleConstr or item.len < 3:
      continue

    var c: InferredConstraint
    c.paramName = item[0].strVal
    let kindStr = item[1].strVal
    let constraintRepr = item[2].strVal

    c.kind = case kindStr
      of "static": ckStatic
      of "typeclass": ckTypeClass
      else: ckNone

    if constraintRepr.len > 0:
      c.constraint = ident(constraintRepr)
    else:
      c.constraint = newEmptyNode()

    result.add c

proc mergeConstraints*(
  explicit: seq[NimNode],
  inferred: seq[InferredConstraint]
): seq[NimNode] =
  ## Merge explicitly provided constraints with inferred ones.
  ##
  ## Rules:
  ## - Explicit constraints take precedence
  ## - Inferred constraints fill in for unconstrained params
  ## - Returns the final list of type parameters with constraints
  result = @[]
  var seen = initTable[string, bool]()

  # First, add all explicit constraints
  for param in explicit:
    var paramName: string
    if param.kind == nnkExprColonExpr:
      # Has constraint: N: static int
      paramName = param[0].strVal
    elif param.kind == nnkIdent:
      # No constraint: N
      paramName = param.strVal
    else:
      paramName = param.repr

    seen[paramName] = true
    result.add param.copyNimTree

  # Then, add inferred constraints for params not already seen
  for c in inferred:
    if c.paramName notin seen:
      result.add buildConstraintNode(c)
      seen[c.paramName] = true

proc hasUnconstrainedParams*(typeParams: seq[NimNode]): bool =
  ## Check if any type parameters lack constraints.
  ##
  ## Returns true if any param is just an ident (like `N`)
  ## rather than a constrained form (like `N: static int`).
  for p in typeParams:
    if p.kind == nnkIdent:
      return true
  return false

proc hasGenericStates*(stateNodes: seq[NimNode]): bool =
  ## Check if any state types have generic parameters.
  ##
  ## Returns true if any state is a BracketExpr (like `StateA[N]`).
  for s in stateNodes:
    if s.kind == nnkBracketExpr:
      return true
  return false

proc extractStateBaseNames*(statesSection: NimNode): seq[NimNode] =
  ## Extract base type names from a states section.
  ##
  ## For `states StateA[N], StateB[N]`, returns `@[StateA, StateB]`
  result = @[]
  for i in 1..<statesSection.len:
    let stateNode = statesSection[i]
    case stateNode.kind
    of nnkBracketExpr:
      result.add stateNode[0].copyNimTree
    of nnkIdent, nnkSym:
      result.add stateNode.copyNimTree
    of nnkStmtList:
      # Multiline states block
      for child in stateNode:
        if child.kind == nnkBracketExpr:
          result.add child[0].copyNimTree
        elif child.kind in {nnkIdent, nnkSym}:
          result.add child.copyNimTree
    else:
      discard

macro inferConstraintsTyped*(T: typedesc): seq[tuple[name: string, kind: string, constraint: string]] =
  ## Typed macro to infer constraints from a single state type.
  ##
  ## Returns a compile-time sequence that can be used in static blocks.
  let typeNode = T.getType()
  result = nnkBracket.newTree()

  if typeNode.kind == nnkBracketExpr and typeNode.len >= 2:
    let typeSym = typeNode[1]
    let constraints = extractConstraintsFromType(typeSym)

    for c in constraints:
      let kindStr = case c.kind
        of ckNone: "none"
        of ckStatic: "static"
        of ckTypeClass: "typeclass"
      let constrStr = if c.constraint.kind != nnkEmpty: c.constraint.repr else: ""

      result.add nnkTupleConstr.newTree(
        newStrLitNode(c.paramName),
        newStrLitNode(kindStr),
        newStrLitNode(constrStr)
      )

  result = nnkPrefix.newTree(ident("@"), result)

proc augmentTypeParams*(
  typeParams: seq[NimNode],
  constraints: seq[tuple[name: string, kind: string, constraint: string]]
): seq[NimNode] =
  ## Augment unconstrained type parameters with inferred constraints.
  ##
  ## For each unconstrained param (just an ident), look up the constraint
  ## from the inferred data and add it.
  result = @[]

  for p in typeParams:
    if p.kind == nnkIdent:
      # Unconstrained - look for inferred constraint
      let paramName = p.strVal
      var found = false
      for c in constraints:
        if c.name == paramName:
          found = true
          case c.kind
          of "static":
            result.add nnkExprColonExpr.newTree(
              ident(paramName),
              nnkCommand.newTree(ident("static"), ident(c.constraint))
            )
          of "typeclass":
            result.add nnkExprColonExpr.newTree(
              ident(paramName),
              ident(c.constraint)
            )
          else:
            result.add p.copyNimTree
          break
      if not found:
        result.add p.copyNimTree
    else:
      # Already constrained - keep as is
      result.add p.copyNimTree
