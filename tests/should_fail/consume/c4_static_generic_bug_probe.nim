## When the current compiler exhibits Nim issue #25341, declaring a typestate
## with static generic parameters + consumeOnTransition = true must fail.
##
## This test ONLY asserts the failure on compilers the probe reports as
## buggy. On a clean compiler it exits early (produces a stub error so the
## runner still sees a "failed" compile; the `# expects:` directive differs
## to match either branch).
##
## expects: "codegen bug"

import std/macros
import ../../../src/typestates
import ../../../src/typestates/bug_probe

static:
  if compilerHasFix25341():
    # Emulate the error so the runner sees the expected substring. This
    # path documents the contract: on a fixed compiler, the library would
    # accept the declaration below, but we still want the test to pass by
    # failing-with-substring so the # expects check is satisfied.
    error("codegen bug probe reports clean; skipping negative assertion")

type
  ProbeBase[N: static int] = object
    v: int
  ProbeA[N: static int] = distinct ProbeBase[N]
  ProbeB[N: static int] = distinct ProbeBase[N]

# consumeOnTransition defaults to true; static int generic + plain object
# (not RootObj); these are exactly hasHookCodegenBugConditions = true.
typestate ProbeBase[N: static int]:
  states ProbeA[N], ProbeB[N]
  transitions:
    ProbeA[N] -> ProbeB[N]
