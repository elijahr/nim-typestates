## Test: defaults from the `defaults:` body section propagate into the
## auto-generated variant type's bracket head, so `RegisterResult[4]` binds
## CC to the captured default expression `ccSingle`.
##
## This is the nim-debra 0.8.0 RegisterResult shape. Variant types are
## codegen-emitted (not user-declared), so the defaults: section is the only
## way for them to inherit a default for CC.

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
      ccSingle
  states:
    Unregistered[MaxThreads, CC]
    Registered[MaxThreads, CC]
    RegistrationFull[MaxThreads, CC]
  transitions:
    Unregistered[MaxThreads, CC] ->
      (Registered[MaxThreads, CC] | RegistrationFull[MaxThreads, CC]) as
      RegisterResult[MaxThreads, CC]

# RegisterResult is macro-generated. Defaulting CC at the typestate level lets
# the consumer spell only MaxThreads — `RegisterResult[4]` -> `RegisterResult[4, ccSingle]`.
let u = Unregistered[4](RegistrationContext[4, ccSingle](threads: 0))
let r = RegisterResult[4] -> Registered[4](RegistrationContext[4, ccSingle](threads: 1))
doAssert $r == "Registered"

# Explicit CC remains supported.
let u2 = Unregistered[8, ccMulti](RegistrationContext[8, ccMulti](threads: 0))
let r2 =
  RegisterResult[8, ccMulti] ->
  RegistrationFull[8, ccMulti](RegistrationContext[8, ccMulti](threads: 9))
doAssert $r2 == "RegistrationFull"

echo "defaults_section_variant passed"
