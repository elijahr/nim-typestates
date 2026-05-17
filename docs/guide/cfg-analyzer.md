# CFG Analyzer (v0.9.0)

The v0.9.0 release adds a control-flow-graph analyzer pass to
`verifyTypestates()`. It walks every registered proc body and rejects exit
edges (return, raise, fall-through, discard, break-escapes-scope) that
leave a typestate-bearing local in a non-terminal state.

## The α Decision (Enabled by Default)

The CFG analyzer is **enabled by default** in v0.9.0. It is a soft-breaking
change under pre-1.0 SemVer §4 latitude:

> "Major version zero (0.y.z) is for initial development. Anything MAY
> change at any time." — SemVer 2.0 §4

Code that compiled and verified under 0.8.0 may newly fail verification
under 0.9.0 when the analyzer surfaces a latent early-return-out-of-typestate
bug. The pre-1.0 latitude is being spent here on a correctness-improving
diagnostic, not on churn: an empirical audit of two downstream consumers
(50 in-tree `{.transition.}` procs across nim-debra 0.8.0 and
lockfreequeues 4.1.x) found 49/50 safe and 1 that needed the
`{.skipCfgAnalysis.}` escape hatch.

## What the Analyzer Enforces

For each tracked local of a typestate-bearing type, the analyzer requires
that **every exit edge** leaves the local in a terminal state — OR that the
local's type has a registered `{.destructorTransition.}` whose `=destroy`
fires automatically.

Tracked locals come from two sources:

1. Locals whose declared type is a state in a registered typestate, e.g.
   `var f: Open` where `Open` belongs to `typestate File:`.
2. Locals whose declared type is bound via the v0.9.0 typestate-attachment
   pragma (`type T {.MyTypestate: InitialState.} = object`); see the
   [Destructor Transitions](destructor-transitions.md) guide.

Exit edges checked:

- `return` (explicit and from `result = ...; return`)
- `raise`
- Fall-through at end of proc body
- `break` / `continue` that escape the local's lexical scope
- `discard expr` where `expr`'s static type is the typestate

## Diagnostic Codes

| ID | When it fires |
|---|---|
| CFG-001 | A live typestate local is non-terminal at an exit edge, and its type has no `{.destructorTransition.}` to bridge it. |
| CFG-002 | Two `if` / `case` branches leave the same local in incompatible non-terminal states; the merge point cannot be reconciled. |
| CFG-003 | `discard expr` where `expr`'s static type is a typestate state that is NOT a declared terminal. |

Every diagnostic is attributed to the exact exit-edge node (return, raise,
discard, branch merge) and includes the local's current state, the
typestate's terminal states, and a hint pointing at this page.

## Worked Example: 0.8.0 Accepted → 0.9.0 Rejects

```nim
import typestates

type
  Connection = object
  Active = distinct Connection
  Closed = distinct Connection

typestate Connection:
  consumeOnTransition = false
  strictTransitions = false
  states Active, Closed
  initial:
    Active
  terminal:
    Closed
  transitions:
    Active -> Closed

proc close(c: sink Active): Closed {.transition.} =
  result = Closed(c.Connection)

proc handle(cond: bool) {.notATransition.} =
  var c = Active(Connection())
  if cond:
    return                  # CFG-001 in 0.9.0: `c` is still Active
  discard close(move c)

verifyTypestates()
```

0.8.0: silently accepted. The `Active` local on the early-return path
never reached `Closed`.

0.9.0: rejected with CFG-001 on the `return` statement.

**Minimal fix — consume on both paths:**

```nim
proc handle(cond: bool) {.notATransition.} =
  var c = Active(Connection())
  if cond:
    discard close(move c)
    return
  discard close(move c)
```

**Alternative fix — let a destructor bridge the transition:**

```nim
proc `=destroy`(c: var Active) {.destructorTransition.} =
  discard
  # Real destructor would release c.Connection.handle here.

proc handle(cond: bool) {.notATransition.} =
  var c = Active(Connection())
  if cond:
    return       # destructor fires, bridges Active -> Closed
  discard close(move c)
```

## When the Analyzer is Wrong: `{.skipCfgAnalysis.}`

A small set of patterns defeat conservative flow analysis. The canonical
example is `nim-debra`'s `shutdown` proc: a `try/except` wrapper around a
transition where the analyzer cannot prove the typestate reaches terminal
in the except branch.

For these cases, opt out per-proc:

```nim
proc shutdown(m: sink Manager) {.transition, skipCfgAnalysis.} =
  try:
    m.drain()
  except CatchableError:
    m.forceTerminate()
```

`{.skipCfgAnalysis.}` disables CFG-001 / CFG-002 / CFG-003 diagnostics for
the marked proc body. All other validation (transition graph, raises,
unmarked-proc strict mode) still applies.

### Decision Criteria

| Symptom | Likely diagnosis | Action |
|---|---|---|
| Early `return` leaves a local non-terminal that you forgot to consume. | Real bug. | Restructure: consume on every path, or add a destructor. |
| `if`/`case` branches honestly compute different terminals (e.g., `Ok` vs `Aborted`). | Real bug (CFG-002). | Reconcile to a common terminal, or add `as ResultType` branching transition. |
| `try/except` where one arm reaches terminal via a path the analyzer cannot prove. | False positive. | `{.skipCfgAnalysis.}`. |
| Discard of a `Result[State, E]` you know is `Err(...)`. | False positive. | `{.skipCfgAnalysis.}` or destructure the Result. |

Apply `{.skipCfgAnalysis.}` only after confirming the typestate truly
reaches terminal on every path — the pragma silences the analyzer, it
does not prove correctness.

## See Also

- [Destructor Transitions](destructor-transitions.md) — the
  `{.destructorTransition.}` pragma that lets `=destroy` bridge a
  typestate to its terminal state.
- [Verification](verification.md) — `verifyTypestates()` and CLI usage.
