import std/macros

macro debugAst(body: untyped): untyped =
  echo body.treeRepr
  result = newStmtList()

# Try command syntax
debugAst:
  states Closed, Open, Errored
  transitions:
    Closed -> Open
    Open -> Closed
