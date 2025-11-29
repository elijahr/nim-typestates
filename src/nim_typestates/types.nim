import std/[macros, tables]

type
  State* = object
    name*: string
    typeName*: NimNode  # The actual type identifier

  Transition* = object
    fromState*: string
    toStates*: seq[string]  # Can be multiple for branching (A -> B | C)
    isWildcard*: bool       # True if fromState is "*"
    declaredAt*: LineInfo   # For error messages

  TypestateGraph* = object
    name*: string
    states*: Table[string, State]
    transitions*: seq[Transition]
    isSealed*: bool
    strictTransitions*: bool
    declaredAt*: LineInfo

proc hasTransition*(graph: TypestateGraph, fromState, toState: string): bool =
  ## Check if a transition from fromState to toState is valid
  for t in graph.transitions:
    if t.isWildcard or t.fromState == fromState:
      if toState in t.toStates:
        return true
  return false

proc validDestinations*(graph: TypestateGraph, fromState: string): seq[string] =
  ## Get all valid destination states from a given state
  result = @[]
  for t in graph.transitions:
    if t.isWildcard or t.fromState == fromState:
      for dest in t.toStates:
        if dest notin result:
          result.add dest
