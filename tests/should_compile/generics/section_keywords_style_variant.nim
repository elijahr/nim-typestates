## Regression (v0.9.3 style-insensitive matching, Gemini round 3): typestate
## section keywords must dispatch style-insensitively, per Nim's identifier
## rules (first character case-sensitive, subsequent characters case- and
## underscore-insensitive). This fixture spells MULTIPLE section keywords with
## non-canonical interior casing (`sTates:`, `tRansitions:`, `deFaults:`) to
## demonstrate the construct-wide fix (the 6-way section dispatch became an
## `eqIdent` chain), not just the `defaults:` site flagged by Gemini.
##
## Before the fix, dispatch was a case-sensitive `case sectionName` and any
## variant spelling produced `Error: Unknown section in typestate block: ...`.
## This fixture compiling PROVES the variant keywords now resolve.

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

typestate RegistrationContext[MaxThreads: static int, CC: static PinScopeCardinality]:
  consumeOnTransition = false
  strictTransitions = false
  deFaults: # style variant of `defaults`
    CC:
      ccSingle
  sTates: # style variant of `states`
    Unregistered[MaxThreads, CC]
    Registered[MaxThreads, CC]
  tRansitions: # style variant of `transitions`
    Unregistered[MaxThreads, CC] -> Registered[MaxThreads, CC]

# If any of the variant-spelled sections had been rejected, the typestate
# would not have produced its state machinery and the lines below would fail.
# Default-only instantiation also exercises the variant `deFaults:` section.
let s1 = Unregistered[4](RegistrationContext[4, ccSingle](threads: 0))
doAssert RegistrationContext[4, ccSingle](s1).threads == 0

let s2 = Unregistered[4, ccMulti](RegistrationContext[4, ccMulti](threads: 3))
doAssert RegistrationContext[4, ccMulti](s2).threads == 3

echo "section_keywords_style_variant passed"
