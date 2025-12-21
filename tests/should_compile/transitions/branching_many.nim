## Test: Many branching destinations
import ../../../src/typestates

type
  Router = object
    path: int

  Start = distinct Router
  PathA = distinct Router
  PathB = distinct Router
  PathC = distinct Router
  PathD = distinct Router
  PathE = distinct Router

typestate Router:
  consumeOnTransition = false # Opt out for existing tests
  strictTransitions = false
  states Start, PathA, PathB, PathC, PathD, PathE
  transitions:
    Start -> (PathA | PathB | PathC | PathD | PathE) as RouteResult
    PathA -> Start
    PathB -> Start
    PathC -> Start
    PathD -> Start
    PathE -> Start

proc routeA(r: Start): PathA {.transition.} =
  PathA(r.Router)

proc routeB(r: Start): PathB {.transition.} =
  PathB(r.Router)

proc routeC(r: Start): PathC {.transition.} =
  PathC(r.Router)

proc routeD(r: Start): PathD {.transition.} =
  PathD(r.Router)

proc routeE(r: Start): PathE {.transition.} =
  PathE(r.Router)

proc reset(r: PathA): Start {.transition.} =
  Start(r.Router)

proc reset(r: PathB): Start {.transition.} =
  Start(r.Router)

proc reset(r: PathC): Start {.transition.} =
  Start(r.Router)

proc reset(r: PathD): Start {.transition.} =
  Start(r.Router)

proc reset(r: PathE): Start {.transition.} =
  Start(r.Router)

let r = Start(Router())
let pathC = r.routeC()
let back = pathC.reset()
doAssert back is Start
echo "branching_many test passed"
