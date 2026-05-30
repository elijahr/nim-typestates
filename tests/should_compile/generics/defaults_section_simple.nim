## Test: typestate generic param with a default declared via `defaults:` body
## section. Consumer instantiates without spelling the defaulted param and
## resolves to the default everywhere.
##
## The DSL extension is: `defaults: CC: ccSingle` inside the typestate body
## propagates through `buildGenericParams` into the generic-params slot of
## every macro-generated type and proc (state enum binding procs, copy
## hooks, branch types, branch constructors, branch operators, `$`
## overloads, `match` macros, and the attachment marker). User-declared
## state distincts and the context type carry the default natively via
## standard Nim `= ccSingle` syntax — the macro's job is to inherit those
## defaults onto every helper it emits.

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
    Unregistered[MaxThreads, CC] -> Registered[MaxThreads, CC]
    Registered[MaxThreads, CC] -> RegistrationFull[MaxThreads, CC]

# Default-only instantiation: CC binds to ccSingle via the captured default.
let s1 = Unregistered[4](RegistrationContext[4, ccSingle](threads: 0))
doAssert RegistrationContext[4, ccSingle](s1).threads == 0

# Explicit CC still works.
let s2 = Unregistered[4, ccMulti](RegistrationContext[4, ccMulti](threads: 3))
doAssert RegistrationContext[4, ccMulti](s2).threads == 3

echo "defaults_section_simple passed"
