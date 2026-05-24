## Test: defaults: with the same param listed twice fires a macro-time
## error. Validates the no-duplicates rule.
##
## expects: "defaults: 'CC' is listed more than once"

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
    CC:
      mRead
    CC:
      mWrite # ERROR: CC listed twice
  states:
    Init[MaxThreads, CC]
