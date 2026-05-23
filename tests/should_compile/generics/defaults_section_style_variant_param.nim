## Regression (v0.9.3 style-insensitive matching, Gemini round 3): a
## `defaults:` entry whose param name is a STYLE VARIANT of the declared
## bracket-head param must still bind. The param is declared `CC` but the
## default entry spells it `Cc`; per Nim's identifier rules (first character
## case-sensitive, subsequent characters case- and underscore-insensitive)
## these are the same identifier, so the default must bind.
##
## Before the fix the entry name was matched with raw `strVal ==`, so the
## variant spelling produced `Error: 'Cc' does not match any generic param`
## and the default was never bound. This fixture mirrors
## `defaults_section_simple.nim` (which proves default binding via a single
## bracket arg that leaves the defaulted param implicit) but spells the
## defaults entry with the `Cc` variant — so compiling AND the default-only
## instantiation working PROVES the style-insensitive param match is fixed.

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
    Cc: # style variant of declared param `CC` — must still bind
      ccSingle
  states:
    Unregistered[MaxThreads, CC]
    Registered[MaxThreads, CC]
    RegistrationFull[MaxThreads, CC]
  transitions:
    Unregistered[MaxThreads, CC] -> Registered[MaxThreads, CC]
    Registered[MaxThreads, CC] -> RegistrationFull[MaxThreads, CC]

# Default-only instantiation: CC binds to ccSingle via the captured default,
# supplied through the style-variant entry name `Cc`. The single bracket arg
# `[4]` leaves CC implicit; if the default had not bound, this would fail to
# resolve CC.
let s1 = Unregistered[4](RegistrationContext[4, ccSingle](threads: 0))
doAssert RegistrationContext[4, ccSingle](s1).threads == 0

# Explicit CC still works.
let s2 = Unregistered[4, ccMulti](RegistrationContext[4, ccMulti](threads: 3))
doAssert RegistrationContext[4, ccMulti](s2).threads == 3

echo "defaults_section_style_variant_param passed"
