## Test: defaults: entry naming a param that isn't declared in the bracket
## head fires a macro-time error. Validates the rule that defaults must
## reference declared params.
##
## expects: "defaults: 'XX' does not match any generic param"
## expects: "Declared params: MaxThreads, CC"

import ../../../src/typestates

type
  Mode = enum
    mRead
    mWrite

  Ctx[MaxThreads: static int, CC: static Mode] = object
  Init[MaxThreads: static int, CC: static Mode] = distinct Ctx[MaxThreads, CC]

typestate Ctx[MaxThreads: static int, CC: static Mode]:
  consumeOnTransition = false
  strictTransitions = false
  defaults:
    XX:
      mRead # ERROR: XX is not declared in the bracket head
  states:
    Init[MaxThreads, CC]
