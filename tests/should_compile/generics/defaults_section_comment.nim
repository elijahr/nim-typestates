## Test: a `defaults:` entry tolerates doc (`##`) and line (`#`) comments
## between the param name and its default value. Such comments are parsed as
## `nnkCommentStmt` nodes; the parser must skip them rather than count them as
## a second default expression. Regression guard for the `defaults:` entry
## child filter in `src/typestates/parser.nim` (mirrors codegen.nim's
## `notin {nnkEmpty, nnkCommentStmt}` filter).

import ../../../src/typestates

type
  PinScopeCardinality = enum
    ccSingle
    ccMulti

  RegistrationContext[MaxThreads: static int, CC: static PinScopeCardinality = ccSingle] = object
    threads: int

  Unregistered[MaxThreads: static int, CC: static PinScopeCardinality = ccSingle] =
    distinct RegistrationContext[MaxThreads, CC]

  Registered[MaxThreads: static int, CC: static PinScopeCardinality = ccSingle] =
    distinct RegistrationContext[MaxThreads, CC]

  RegistrationFull[MaxThreads: static int, CC: static PinScopeCardinality = ccSingle] =
    distinct RegistrationContext[MaxThreads, CC]

typestate RegistrationContext[MaxThreads: static int, CC: static PinScopeCardinality]:
  consumeOnTransition = false
  strictTransitions = false
  defaults:
    CC:
      ## doc comment between the param name and its default value
      # line comment too
      ccSingle
  states:
    Unregistered[MaxThreads, CC]
    Registered[MaxThreads, CC]
    RegistrationFull[MaxThreads, CC]
  transitions:
    Unregistered[MaxThreads, CC] -> Registered[MaxThreads, CC]
    Registered[MaxThreads, CC] -> RegistrationFull[MaxThreads, CC]

# Default-only instantiation: CC binds to ccSingle via the captured default,
# proving the comment did not displace the real default expression.
let s1 = Unregistered[4](RegistrationContext[4, ccSingle](threads: 0))
doAssert RegistrationContext[4, ccSingle](s1).threads == 0

# Explicit CC still works.
let s2 = Unregistered[4, ccMulti](RegistrationContext[4, ccMulti](threads: 3))
doAssert RegistrationContext[4, ccMulti](s2).threads == 3

echo "defaults_section_comment passed"
