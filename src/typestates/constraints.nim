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

import std/macros

type
  ConstraintKind* = enum
    ckNone ## No constraint (plain type variable)
    ckStatic ## static constraint (e.g., static int)
    ckTypeClass ## Type class constraint (e.g., SomeNumber)

  InferredConstraint* = object
    ## Represents an inferred constraint for a generic parameter
    paramName*: string
    kind*: ConstraintKind
    constraint*: NimNode ## The constraint AST

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
        let constraintName =
          if paramType[0].kind == nnkSym:
            paramType[0].strVal
          else:
            ""
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

macro inferConstraintsTyped*(
    T: typedesc
): seq[tuple[name: string, kind: string, constraint: string]] =
  ## Typed macro to infer constraints from a single state type.
  ##
  ## Returns a compile-time sequence that can be used in static blocks.
  let typeNode = T.getType()
  result = nnkBracket.newTree()

  if typeNode.kind == nnkBracketExpr and typeNode.len >= 2:
    let typeSym = typeNode[1]
    let constraints = extractConstraintsFromType(typeSym)

    for c in constraints:
      let kindStr =
        case c.kind
        of ckNone: "none"
        of ckStatic: "static"
        of ckTypeClass: "typeclass"
      let constrStr = if c.constraint.kind != nnkEmpty: c.constraint.repr else: ""

      result.add nnkTupleConstr.newTree(
        newStrLitNode(c.paramName), newStrLitNode(kindStr), newStrLitNode(constrStr)
      )

  result = nnkPrefix.newTree(ident("@"), result)
