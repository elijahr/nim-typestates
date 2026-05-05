## Regression: `match` macro must expand correctly when invoked from a generic
## proc body whose call site does NOT directly import the kind enum module.
##
## Before v0.7.2 the generated `match` macro emitted bare `ident(prefix &
## stateName)` nodes for the `case` arms (e.g. `oOk`, `oErr`). Those idents
## had to resolve at the consumer's call site. Generic procs are instantiated
## in the consumer's compile context, so when the consumer imported a facade
## that did not re-export the kind enum's defining module, instantiation
## failed with "undeclared identifier: 'oOk'".
##
## Real-world repro: lockfreequeues `t_mupmuc.nim` -> `lockfreequeues` ->
## `mupmuc.nim` (imports but does not export `./typestates/mpmc_push`).
##
## v0.7.2 fix: the generated `match` macro pre-resolves kind-enum syms via
## `bindSym` at decl time (where the kind enum IS in scope) and threads them
## into `buildMatchCase`, so consumer-site visibility no longer matters.
##
## This test imports ONLY the wrapper module (mirroring the lockfreequeues
## facade pattern). The wrapper imports the typestate-defining module but
## does not re-export it, so the kind enum is not visible from this file.
import ../../fixtures/match_consumer_wrapper

doAssert runOutcome[string](Pending(Payload(body: "yes")), "ok", "err") == "ok"
doAssert runOutcome[string](Pending(Payload(body: "no")), "ok", "err") == "err"
doAssert runOutcome[int](Pending(Payload(body: "yes")), 1, 0) == 1
doAssert runOutcome[int](Pending(Payload(body: "no")), 1, 0) == 0

echo "match_external_consumer test passed"
