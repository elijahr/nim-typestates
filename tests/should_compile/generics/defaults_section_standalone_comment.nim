## Test: a `defaults:` block tolerates a STANDALONE doc comment (`##`) written
## on its own line inside the block, before/between entries. Such a comment
## survives parsing as a top-level `nnkCommentStmt` child of the defaults body
## (unlike plain `#` line comments, which the parser strips entirely). The
## top-level entry loop in `src/typestates/parser.nim` must skip these comment
## nodes rather than treating them as malformed entries. Regression guard:
## before the fix, a standalone `##` line errored with
## "got node kind nnkCommentStmt".

import ../../../src/typestates

type
  PinScopeCardinality = enum
    ccSingle
    ccMulti

  RegistrationContext[
    MaxThreads: static int = 4, CC: static PinScopeCardinality = ccSingle
  ] = object
    threads: int

  Unregistered[MaxThreads: static int = 4, CC: static PinScopeCardinality = ccSingle] =
    distinct RegistrationContext[MaxThreads, CC]

  Registered[MaxThreads: static int = 4, CC: static PinScopeCardinality = ccSingle] =
    distinct RegistrationContext[MaxThreads, CC]

  RegistrationFull[
    MaxThreads: static int = 4, CC: static PinScopeCardinality = ccSingle
  ] = distinct RegistrationContext[MaxThreads, CC]

typestate RegistrationContext[MaxThreads: static int, CC: static PinScopeCardinality]:
  consumeOnTransition = false
  strictTransitions = false
  defaults:
    ## standalone doc comment before the first entry
    MaxThreads:
      4
    ## standalone doc comment between two entries
    CC:
      ccSingle
  states:
    Unregistered[MaxThreads, CC]
    Registered[MaxThreads, CC]
    RegistrationFull[MaxThreads, CC]
  transitions:
    Unregistered[MaxThreads, CC] -> Registered[MaxThreads, CC]
    Registered[MaxThreads, CC] -> RegistrationFull[MaxThreads, CC]

# Default-only instantiation: CC binds to ccSingle via the captured default,
# proving the standalone comments did not displace or corrupt the real default
# entries.
let s1 = Unregistered[4](RegistrationContext[4, ccSingle](threads: 0))
doAssert RegistrationContext[4, ccSingle](s1).threads == 0

# Explicit CC override still works.
let s2 = Unregistered[8, ccMulti](RegistrationContext[8, ccMulti](threads: 3))
doAssert RegistrationContext[8, ccMulti](s2).threads == 3

echo "defaults_section_standalone_comment passed"
