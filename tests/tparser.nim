import std/[macros, tables]
import ../src/typestates/parser
import ../src/typestates/types

macro testParseStates(): untyped =
  # Simulate AST for: states: Closed, Open, Errored
  let statesNode =
    nnkCall.newTree(ident("states"), ident("Closed"), ident("Open"), ident("Errored"))

  var graph = TypestateGraph(name: "File")
  parseStates(graph, statesNode)

  doAssert graph.states.len == 3
  doAssert "Closed" in graph.states
  doAssert "Open" in graph.states
  doAssert "Errored" in graph.states

  result = newStmtList()

testParseStates()
echo "parser states test passed"

macro testParseTransition(): untyped =
  # Simulate AST for: Closed -> Open
  let transNode = nnkInfix.newTree(ident("->"), ident("Closed"), ident("Open"))

  var graph = TypestateGraph(name: "File")
  graph.states["Closed"] = State(name: "Closed")
  graph.states["Open"] = State(name: "Open")

  let trans = parseTransition(transNode)

  doAssert trans.fromState == "Closed"
  doAssert trans.toStates == @["Open"]
  doAssert not trans.isWildcard

  result = newStmtList()

testParseTransition()

macro testParseBranchingTransition(): untyped =
  # Simulate AST for: Closed -> Open | Errored as OpenResult
  # The AST structure is: Infix("->", Closed, Infix("as", Infix("|", Open, Errored), OpenResult))
  let transNode = nnkInfix.newTree(
    ident("->"),
    ident("Closed"),
    nnkInfix.newTree(
      ident("as"),
      nnkInfix.newTree(ident("|"), ident("Open"), ident("Errored")),
      ident("OpenResult"),
    ),
  )

  let trans = parseTransition(transNode)

  doAssert trans.fromState == "Closed"
  doAssert trans.toStates.len == 2
  doAssert "Open" in trans.toStates
  doAssert "Errored" in trans.toStates
  doAssert trans.branchTypeName == "OpenResult"

  result = newStmtList()

testParseBranchingTransition()

macro testParseWildcard(): untyped =
  # Simulate AST for: * -> Closed
  # In Nim, standalone * parses as nnkIdent("*")
  let transNode = nnkInfix.newTree(ident("->"), ident("*"), ident("Closed"))

  let trans = parseTransition(transNode)

  doAssert trans.fromState == "*"
  doAssert trans.toStates == @["Closed"]
  doAssert trans.isWildcard

  result = newStmtList()

testParseWildcard()

echo "parser transition tests passed"

macro testParseFullBlock(): untyped =
  # Simulate the body of:
  # typestate File:
  #   states: Closed, Open, Errored
  #   transitions:
  #     Closed -> Open | Errored as OpenResult
  #     Open -> Closed
  #     * -> Closed

  let body = nnkStmtList.newTree(
    nnkCall.newTree(ident("states"), ident("Closed"), ident("Open"), ident("Errored")),
    nnkCall.newTree(
      ident("transitions"),
      nnkStmtList.newTree(
        nnkInfix.newTree(
          ident("->"),
          ident("Closed"),
          nnkInfix.newTree(
            ident("as"),
            nnkInfix.newTree(ident("|"), ident("Open"), ident("Errored")),
            ident("OpenResult"),
          ),
        ),
        nnkInfix.newTree(ident("->"), ident("Open"), ident("Closed")),
        nnkInfix.newTree(ident("->"), ident("*"), ident("Closed")),
      ),
    ),
  )

  let graph = parseTypestateBody(ident("File"), body)

  doAssert graph.name == "File"
  doAssert graph.states.len == 3
  doAssert graph.transitions.len == 3
  doAssert graph.hasTransition("Closed", "Open")
  doAssert graph.hasTransition("Closed", "Errored")
  doAssert graph.hasTransition("Open", "Closed")
  doAssert graph.hasTransition("Errored", "Closed") # via wildcard

  result = newStmtList()

testParseFullBlock()

echo "parser full block test passed"

macro testParsePragmas(): untyped =
  # Test setting pragma flags on a graph
  let body = nnkStmtList.newTree(
    nnkCall.newTree(ident("states"), ident("Closed"), ident("Open")),
    nnkCall.newTree(
      ident("transitions"),
      nnkStmtList.newTree(nnkInfix.newTree(ident("->"), ident("Closed"), ident("Open"))),
    ),
  )

  var graph = parseTypestateBody(ident("File"), body)

  # Test setting flags (actual pragma parsing would be added later)
  graph.strictTransitions = true

  doAssert graph.strictTransitions

  result = newStmtList()

testParsePragmas()
echo "pragma parsing test passed"

# Test flag parsing
macro testFlagParsing(): untyped =
  # Test explicit false
  let body1 = quote:
    strictTransitions = false
    states Closed, Open
    transitions:
      Closed -> Open

  var graph1 = parseTypestateBody(ident("File"), body1)
  doAssert graph1.strictTransitions == false, "strictTransitions should be false"

  # Test explicit true (same as default)
  let body2 = quote:
    strictTransitions = true
    states Closed, Open
    transitions:
      Closed -> Open

  var graph2 = parseTypestateBody(ident("File"), body2)
  doAssert graph2.strictTransitions == true, "strictTransitions should be true"

  # Test defaults (no flags specified)
  let body3 = quote:
    states Closed, Open
    transitions:
      Closed -> Open

  var graph3 = parseTypestateBody(ident("File"), body3)
  doAssert graph3.strictTransitions == true, "strictTransitions should default to true"

  result = newStmtList()

testFlagParsing()
echo "flag parsing tests passed"
