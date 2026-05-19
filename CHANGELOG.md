# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.9.1] - 2026-05-19

### Documentation

- **Green Mirage postmortem (AGENTS.md).** Captured a recurring failure
  mode observed during the v0.9.0 destructor-transition cycle: an
  over-conservative `if isSink: continue` skip introduced to suppress a
  single observed false-fire (canonical `result = Dst(s.Base)` shape)
  silently hid a soundness gap on every sink-T transition proc that
  failed to consume its sink param. The gap survived four review rounds
  before Gemini surfaced it; remediation required reverting the skip
  and threading the consumption-recognition fix through the call-shape
  extractor instead. The rule: when introducing a default-deny / skip
  predicate to suppress a false-fire, audit the blast radius — what
  class of real errors does the predicate now exempt from analysis?
  Often the right fix is to improve the under-recognition that caused
  the false-fire, not to skip the whole category.
- Internal documentation only. No behavioural changes; no public API
  changes; all 219 tests + 116 fixtures from v0.9.0 continue to pass.

## [0.9.0] - 2026-05-19

### Breaking (pre-1.0 latitude)

- **CFG analyzer enabled by default.** A new control-flow-graph pass
  inside `verifyTypestates()` rejects exit edges (return, raise,
  fall-through, discard, scope-escaping break/continue) that leave a
  typestate-bearing local in a non-terminal state. The analyzer tracks
  state transitions through call, assignment, var/let-init, and
  sink-consume positions for registered `{.transition.}` and
  `{.destructorTransition.}` procs, and resolves identifier shadowing
  innermost-first. Branch reconciliation rejects locals consumed in
  some branches but left non-terminal in others (CFG-002). Code that
  compiled and verified under 0.8.0 may newly fail verification under
  0.9.0 when the analyzer surfaces a latent early-return-out-of-typestate
  bug. This is a soft-breaking change covered by pre-1.0 SemVer 2.0 §4
  latitude; an empirical audit of two downstream consumers (50
  `{.transition.}` procs across nim-debra 0.8.0 + lockfreequeues 4.1.x)
  found 49/50 safe and 1 that needed the `{.skipCfgAnalysis.}` escape
  hatch. See [docs/guide/cfg-analyzer.md](docs/guide/cfg-analyzer.md)
  for the migration guide, recognized transition shapes, decision
  criteria, and the escape hatch.
- **`{.destructorTransition.}` required on typestate `=destroy` hooks.**
  Nim `=destroy` hooks for a typestate-bearing type that perform the
  terminal transition must declare `{.destructorTransition.}` so the CFG
  analyzer recognizes the auto-consumption at scope exits. Existing
  destructors that did not perform a transition are unaffected; existing
  destructors that did perform one were previously invisible to
  verification and now require the pragma. See
  [docs/guide/destructor-transitions.md](docs/guide/destructor-transitions.md).
- **Same-name typestate compile-warning.** When a typestate's name
  collides with the name of an object type in the same module (e.g.,
  `typestate Resource:` + `type Resource = object`), the per-typestate
  attachment-pragma macro cannot be emitted (Nim does not allow
  redefinition). Codegen now emits a `{.warning.}` at use-site naming the
  colliding typestate and suggesting a `<Name>Context` rename. Distinct-name
  typestates are unaffected. This is a documented constraint of the §3.7
  attachment pragma, not a regression: legacy same-name typestates that
  never used attachment continue to compile and verify unchanged.

### Added

- **`{.destructorTransition.}` pragma (two arities).**
    - Single-arg: `proc \`=destroy\`(f: var Open) {.destructorTransition.}`.
      Destination state inferred as the typestate's `terminalStates` set.
    - Two-arg: `proc \`=destroy\`(c: var Halfopen)
      {.destructorTransition: Halfopen -> Closed.}`. Destination state
      explicit; spec validated against the typestate graph.
    - Auto-injects `{.raises: [].}` when absent.
    - Compile-time diagnostic catalog: DT-001..DT-011, DT-013.
- **`{.skipCfgAnalysis.}` pragma.** Per-proc opt-out for the CFG
  analyzer. Use sparingly for verified false positives.
- **Typestate-attachment pragma.** Per-typestate macro emitted by the
  `typestate` macro of the form `{.<TypestateName>: <InitialState>.}`,
  applied to an object type declaration to bind that type to a typestate
  with an initial state. Only available when the typestate name differs
  from the attached object type (see Breaking above). Compile-time
  diagnostic catalog: TA-001..TA-004.
- **CFG analyzer diagnostic codes.** CFG-001 (missed terminal at exit
  edge), CFG-002 (branch reconciliation mismatch), CFG-003 (discard of
  non-terminal typestate value).
- **Public registry surface** in `src/typestates/registry.nim`:
  `type AttachmentInfo*`, `var typestateAttachments* {.compileTime.}`,
  `proc findAttachmentForType*`, `proc addAttachment*`.
- New documentation:
  [Destructor Transitions](docs/guide/destructor-transitions.md) and
  [CFG Analyzer](docs/guide/cfg-analyzer.md). New example:
  `examples/destructor_transition_example.nim`.

### Fixed

- **`peelNameWrappers` loops until a leaf and `extractTypeDeclName`
  handles `nnkAccQuoted` at both top-level and BracketExpr-head
  positions.** Round-18 defensive consistency on the r17 shared
  helpers. `peelNameWrappers` was single-pass (one `nnkPragmaExpr`
  peel followed by one `nnkPostfix` peel), so hand-built ASTs with
  the inverse `Postfix(PragmaExpr(...))` ordering or deeper nesting
  left a residual wrapper on the returned node; the helper now loops
  while the kind is in `{nnkPragmaExpr, nnkPostfix}` and drains every
  layer. `extractTypeDeclName` previously fell through to `.repr`
  for backticked type names (`type \`foo\` = object`), preserving
  the backticks and breaking attachment-registry lookups that key
  off the bare identifier; the proc now dispatches on `nnkAccQuoted`
  at the top-level case AND inside the `nnkBracketExpr` head case,
  reassembling the bare name via `accQuotedToStr` to match
  `extractTypestatedParams` and `destructorTransitionCore`. Neither
  shape is reachable from natural Nim parser output, but both are
  reachable from downstream macros that hand-build TypeDef ASTs.
  `tests/textract_type_decl_name.nim` extended with three backtick
  cases (`\`foo\``, `\`foo\`*`, `\`foo\`*[G]`) and a
  three-block arbitrary-wrapper-nesting case
  (inverse Postfix-outside-PragmaExpr, three-deep PragmaExpr/Postfix
  alternation, double Postfix). All 215 prior comprehensive-runner
  tests continue to pass byte-identical.
- **`destructorTransitionCore` proc-name extraction unwraps
  `nnkPragmaExpr` before the `nnkPostfix` peel.** Round-16
  (Gemini r15) surfaced a narrow-shape gap on the destructor
  proc-name extractor: when a `=destroy` hook was BOTH exported AND
  carried extra pragmas (e.g.
  `proc \`=destroy\`* {.inline, destructorTransition.}(...)`), Nim
  parsed the proc-name slot as
  `PragmaExpr(Postfix(*, AccQuoted(=, destroy)), Pragma)`. The
  extractor peeled only a top-level `nnkPostfix`, left the
  `nnkPragmaExpr` in place, and the case-dispatch fell through to
  `procNameNode.repr` — returning the full wrapped form. The
  `procName != "=destroy"` discriminator then errored out with a
  misleading "may only be applied to a `=destroy` hook" diagnostic
  on a syntactically valid destructor. Post-fix the unwrap precedence
  mirrors `extractTypeDeclName` (pragmas.nim:1052-1057): peel
  `nnkPragmaExpr`, then `nnkPostfix`, then dispatch on the leaf
  `nnkAccQuoted` / `nnkIdent` / `nnkSym` node. New fixtures:
  `tests/should_compile/pragmas/destructor_transition_exported_with_pragma.nim`
  (exported + extra-pragma destructor compiles) and
  `tests/should_fail/pragmas/destructor_transition_exported_with_pragma_wrong_name.nim`
  (DT-002 still fires on a non-`=destroy` proc with the same wrapper
  shape, confirming the unwrap exposes the real name to the
  discriminator rather than masking it).
- **`extractTypestatedParams` param-name unwrap systematized to
  handle nested wrappers.** Round-16 (Gemini r15) extended the
  same precedence chain to the param-name extractor inside
  `extractTypestatedParams`. The pre-fix code dispatched on the
  outer wrapper kind: the `nnkPragmaExpr` branch inspected only
  `[0].kind in {nnkIdent, nnkSym}`, so a hand-built procDef with
  `PragmaExpr(Postfix(*, p), Pragma)` (Nim's parser rejects this
  shape from user source — `proc f(p* {.x.}: T)` fails with
  "identifier expected, but found 'p*'", but a downstream macro
  synthesizing a procDef AST can emit it) skipped the param entry
  silently, and `nnkAccQuoted` names were not recognised at all.
  Post-fix the extractor peels `nnkPragmaExpr` then `nnkPostfix`
  before dispatching on the leaf, accepting `nnkIdent` / `nnkSym` /
  `nnkAccQuoted`. New unit test
  `tests/textract_typestated_params_name_shapes.nim` asserts the
  five recognised shapes (bare ident, postfix, pragma-decorated,
  nested postfix-in-pragmaExpr, AccQuoted-in-pragmaExpr) against
  hand-built procDef ASTs with a registered typestate graph. New
  end-to-end fixture
  `tests/should_compile/pragmas/typestate_param_with_pragma.nim`
  exercises the user-reachable `p {.userPragma.}: var Src` shape
  through `{.transition.}` registration.
- **`extractTypeDeclName` handles the exported-generic AST shape and
  three stale comment blocks cleaned up.** Round-15 (Gemini r14)
  surfaced a defensive recognizer gap plus three documentation
  blocks that no longer described the current implementation:
    - `extractTypeDeclName` (pragmas.nim) accepted only `Ident`/`Sym`
      at the head of an `nnkBracketExpr`. The natural Nim parse of
      `type T*[G] = object` puts `nnkPostfix(*, T)` at the TypeDef
      head (handled by the top-level Postfix-unwrap), so the
      BracketExpr branch was not exercised in the primary path —
      but any downstream macro that synthesizes a
      `BracketExpr(Postfix(*, T), G)` shape would have hit the
      fallback `head.repr` and returned a name with the stale `*`
      export marker, causing §3.7 attachment-registry lookups to
      miss. The round-15 patch peels a nested `nnkPostfix` inside
      the BracketExpr branch, mirroring the top-level unwrap, so
      both AST shapes collapse to the bare base name. New
      load-bearing unit test `tests/textract_type_decl_name.nim`
      asserts the four input shapes (`T`, `T*`, `T[G]`, `T*[G]`)
      directly against hand-built TypeDef ASTs (analogous to the
      round-13 `textract_callee_name.nim` pattern). New end-to-end
      fixtures `tests/should_compile/pragmas/typestate_attachment_exported_type.nim`
      and `typestate_attachment_exported_generic_type.nim` cover the
      attachment-registry path through the natural Nim parse.
    - Sink-param-tracking comment in `extractTypestatedParams`
      (pragmas.nim:334) was updated to reflect round-14's symmetric
      pre-population of `sink T` and `var T` params and the
      conversion-consume path that keeps canonical conversion
      bodies clean.
    - DT-013 entry in the destructor-transition diagnostic catalog
      (pragmas.nim:787) was updated from "deferred" to
      "attached-object-param SrcState mismatch (two-arg only)" —
      DT-013 has been implemented since the §3.7 attachment registry
      landed (see pragmas.nim:916-923).
    - §3.7 attachment-registry stub note in `destructorTransitionCore`'s
      Phase 2 (pragmas.nim:860) was rewritten to describe the now-
      functional registry path: `findAttachmentForType` returns real
      bindings populated by `attachTypestateCore` when a per-typestate
      attachment pragma fires on a type declaration.
- **CFG analyzer: `runCfgAnalyzer` pre-populates sink-typed
  typestate-bearing params symmetrically with `var T` params.**
  Round-14 (Gemini r13 HIGH) reversed the round-9 skip
  (`if tp.isSink: continue`) on the live-set pre-population loop.
  The skip was added on the theory that the canonical
  `proc tx(s: sink Src): Dst; result = Dst(s.Base)` shape would
  false-fire CFG-001 because the body never named the sink param
  textually. Round-7's unified `extractTrackedLocal` already unwraps
  `nnkDotExpr` recursively, and `applyCallTransitions`'
  conversion-consume path (`isStateTypeName(callName)` calling
  `consumeLocalsInSubtree`) drops every tracked local in the
  conversion subtree — so the canonical shape consumes the sink
  param before the fall-through exit edge runs. The skip was
  over-conservative: a sink-T transition body that constructs
  `result` from a fresh value (e.g.,
  `result = Closed(File(h: 0))`) silently passed the analyzer.
  Round-14 tracks sink params symmetrically with `var T` params at
  pre-population; canonical conversion bodies still verify cleanly
  because conversion-consume drops the sink param at the asgn site;
  sink params whose type carries a registered
  `{.destructorTransition.}` remain accepted at exit via the
  destructor short-circuit in `validateExitEdge`. New fixtures
  `cfg_analyzer_sink_param_discarded_in_body` and
  `cfg_analyzer_sink_param_non_terminal_early_return` lock in the
  positive (CFG-001 fires) path; `cfg_analyzer_sink_param_canonical_consumption`
  and `cfg_analyzer_sink_param_destructor_coverage` lock in the
  negative (clean) path. The round-9 sink-overload fixtures
  (`cfg_analyzer_overloaded_sink_transition_var_init`,
  `cfg_analyzer_overloaded_sink_transition_asgn`,
  `cfg_analyzer_tracks_sink_consume`,
  `cfg_analyzer_sink_wrong_state`) continue to verify cleanly
  without re-introducing destructor-coverage workarounds, confirming
  conversion-consume covers every canonical-shape case. No
  known-limitation language.
- **CFG analyzer: branch reconciliation accepts non-consume tail
  when destructor covers the entry-set local.** Round-14 (Gemini
  r13 MEDIUM) closed a parallel destructor-aware gap at the
  consume-side reconciliation site in `reconcileBranches`. When an
  entry-set typestate-bearing local was consumed in one branch and
  left non-terminal in another, the analyzer emitted CFG-002
  ("inconsistent state across branches") without consulting
  `hasDestructorFor`. The branch-introduced-local path below
  (verify.nim lines 1417-1422) already short-circuited via the
  destructor; the consume-side reconciliation was the parallel gap.
  Round-14 mirrors that pattern: for each present-non-terminal
  branch instance, consult `hasDestructorFor` against the
  in-scope `LocalTypestate`. If every non-terminal instance is
  destructor-covered, drop the local from the merged live-set as
  if every branch had consumed it; otherwise emit CFG-002. The
  destructor probe keys on each branch's actual `stateType` +
  `attachedTypeName`, so the lookup remains correct even when a
  branch advanced the local before going out of scope. New fixtures
  `cfg_analyzer_branch_consume_else_destructor` (clean),
  `cfg_analyzer_branch_consume_else_no_destructor` (CFG-002 still
  fires when no destructor is registered), and
  `cfg_analyzer_branch_both_consume` (clean baseline) lock in the
  narrow destructor-only relaxation.
- **CFG analyzer: destructor lookup de-duplicated at the
  `discard` non-terminal validation site.** Round-14 (Gemini r13
  MEDIUM) removed a bespoke direct-table destructor check in the
  `nnkDiscardStmt` handler that was a verbatim restatement of
  `hasDestructorFor`'s body (attached-type-first, then state-type,
  both gated on graph-name match). Every change to the canonical
  lookup had to be mirrored at the bespoke site by hand. The
  round-14 refactor constructs a representative `LocalTypestate`
  from the post-walk `exprStateName` and the recovered
  `attachedKey` (which already handles the round-9 pre-walk
  fall-back when intrinsic-consume drops the local) and delegates
  to `hasDestructorFor`. The post-walk state divergence the
  pre-round-14 comment cited is handled by passing `exprStateName`
  directly into the temp probe's `stateType` field — the helper
  keys on that value, not on whatever the live-set currently holds.
  Behaviour-preserving; existing fixtures continue to verify
  cleanly.
- **CFG analyzer: `extractCalleeName` recognizes module-qualified
  generic call shapes.** Round-13 (Momus r3 BOT-C2) surfaced a
  callee-recognition gap in the `nnkBracketExpr` branch of
  `extractCalleeName` (verify.nim:336). The branch checked
  `head[0].kind in {nnkIdent, nnkSym}` — true for the unqualified
  `foo[T](...)` shape but FALSE for the module-qualified
  `module.foo[T](...)` shape, where the AST nests a `nnkDotExpr`
  inside the bracket-expr: `Call(BracketExpr(DotExpr(module, foo),
  T), args)`. Pre-fix the recognizer returned the empty string, the
  analyzer treated the call as unrecognized, and the downstream
  consumption / LHS-binding paths
  (`applyCallTransitions`, `tryBindLocalFromCallInit`, asgn-from-call
  rebind) silently lost transition tracking. The fix extends the
  bracket-expr branch to dispatch on `head[0].kind` and recurse on
  the dot-expr's trailing identifier, mirroring the precedence of
  the top-level `nnkDotExpr` branch; `nnkOpenSymChoice` /
  `nnkClosedSymChoice` heads at the bracket position are also
  handled symmetrically. Audit-matrix extension over r3/r5/r8/r9/r12:
  each prior round closed a distinct callee head-shape class
  (bare-ident, dot-call, transparent wrappers, sink-overload,
  multi-typestate-param); r13 closes the dot-then-bracket
  cross-module generic shape. Structural unit tests in
  `tests/textract_callee_name.nim` drive the recognizer directly
  with hand-built ASTs across every head shape and lock in the
  post-fix behaviour; the recognizer's pre-fix branches FAIL the
  BOT-C2 case in that suite. A complementary end-to-end fixture
  `cfg_analyzer_module_qualified_generic_call` exercises the
  `module.foo[T](args)` call through a registered generic
  transition. No known-limitation language.
- **CFG analyzer: `tryBindLocalFromCallInit` dead parameter removed.**
  Round-13 (Momus r3 BOT-C1) cleanup. The `destructorTypes:
  Table[string, TypestateGraph]` parameter was present in the
  signature but never referenced in the body — the binding-recovery
  path keys on the registered transition's destination state (via
  `findTransitionByCalleeAndArgStates` + `findTypestateForState`),
  not on the destructor table. Same cleanup class as r8
  (`applyCallTransitions` `destructorTypes` removal) and r11
  (`lookupTypestateForType` `destructorTypes` removal). The single
  call site in `bindLocalsFromIdentDefs` was updated to drop the
  argument. No behaviour change; the analyzer's destructor-keyed
  paths continue to thread `destructorTypes` through the
  `walkCfg` / `validateExitEdge` chain unchanged.
- **Docs: `cfg-analyzer.md` worked-example fix snippets.** Round-13
  (Gemini r12) flagged two uncompilable snippets at lines ~101 and
  ~121: both opened with `var c: Active` even though `Active` is
  `distinct Connection` and the surrounding code does not provide a
  zero-initialiser, so a user copy-pasting the snippet would face a
  type-conversion error before reaching the analyzer's CFG-001
  diagnostic. Replaced with `var c = Active(Connection())` to mirror
  the working snippet earlier in the same guide. Both snippets
  continue to demonstrate their intended analyzer behaviour (consume
  on both paths; destructor bridges the transition). The change is
  verified by extracting each snippet to a standalone `.nim` file
  and running `nim check`.
- **CHANGELOG: `dot_call_intrinsic` fixture-name typo corrected.**
  Round-13 (Gemini r12) flagged a stray hyphen across a line break
  in the round-7 entry — `dot_call_-\n  intrinsic_non_terminal`
  rendered as a different name than the actual fixture file
  `cfg_analyzer_discard_dot_call_intrinsic_non_terminal.nim`. The
  typo was a pure rendering issue (hyphen + soft-wrap, not in the
  fixture name itself); corrected in place to match the canonical
  filename. No code change; CHANGELOG narrative is now consistent
  with the on-disk fixture name.
- **CFG analyzer: `applyCallTransitions` applies per-arg state
  transitions across ALL typestate-bearing parameter positions at a
  call site.** Round-12 (Gemini r11) surfaced a multi-typestate-param
  consumption gap: the per-arg loop in `applyCallTransitions` looked
  up a transition independently for each call-site argument via
  `findRegisteredTransitionForArg`, which keyed on
  `(callName, argStateType)` against the registered proc's first-param
  source-state. For a registered transition with MULTIPLE typestate-
  bearing parameters (e.g. `proc combine(a: sink T1, b: sink T2)`),
  the per-arg lookup for `a` matched (its `argStateType` equalled the
  proc's first-param `sourceState`) and consumed `a`, but the per-arg
  lookup for `b` returned `none` (its `argStateType` did not equal the
  proc's first-param `sourceState`) — `b` stayed in the live-set and
  false-fired CFG-001 at fall-through. The round-9 sink-overload
  fixtures worked around this orthogonal gap via destructor coverage
  on the trailing-param state; Gemini r11 flagged it as a real
  ship-blocker. The fix composes with the existing
  `findTransitionByCalleeAndArgStates` helper (rounds 4/5/9), which
  already considers the full call-site arg-state vector and the
  matched transition's full `typestatedParams` seq. The refactored
  per-arg loop resolves the full transition once, then iterates the
  matched transition's `typestatedParams`, maps each entry's
  `paramIndex` back to the call-site arg position, and applies
  per-arg consumption: sink-typed (or `pkDestructorTransition`-kind)
  params drop the tracked local; non-consuming first-position params
  advance in place to the registered destination; non-consuming
  trailing typestate params drop conservatively (the registration
  captures one return type but no per-trailing-param destination, so
  their post-call state is structurally underspecified). The now-dead
  `findRegisteredTransitionForArg` helper was retired. The round-9
  sink-overload fixtures (`cfg_analyzer_overloaded_sink_transition_var_init`
  and `cfg_analyzer_overloaded_sink_transition_asgn`) had their
  `{.destructorTransition.}` workarounds removed and continue to
  verify cleanly under the round-12 fix, confirming the underlying
  gap is genuinely closed. New fixtures cover the negative-regression
  scenarios:
  `cfg_analyzer_multi_typestate_param_consumption` (basic two-sink
  multi-typestate-param consumption, would fail pre-round-12),
  `cfg_analyzer_multi_typestate_param_overloaded` (composition with
  source-state-aware overload disambiguation across two registered
  overloads sharing the same first-param source-state), and the
  should_fail fixture
  `cfg_analyzer_multi_typestate_param_result_non_terminal` (locks in
  that the multi-typestate consumption does not over-consume — a
  non-terminal LHS return from a multi-param transition still fires
  CFG-001 at fall-through). No known-limitation language.
- **CFG analyzer: `extractTypeNameAst` no longer peels `nnkRefTy` /
  `nnkPtrTy` wrappers.** Round-12 (Gemini r11) flagged the peel as
  dead defense-in-depth. The analyzer does not model heap aliasing
  (documented in the round-9 param-kind audit), and
  `extractTypestatedParams` already excludes `ref T` / `ptr T`
  parameters from the per-proc `typestatedParams` seq at registration
  time, so `extractTypeNameAst` is never invoked on a ref/ptr type
  slot in practice. Peeling the wrappers here masked potential bugs
  in upstream filtering rather than catching them; removing the
  branches keeps the helper's contract aligned with the audited param-
  kind filter. Behavior unchanged; surface narrowed. No
  known-limitation language.
- **CFG analyzer: continue handler validates exit edges.** Round-11
  surfaced a parallel gap to the existing break-handler validation:
  the `continue` handler in `walkCfg` dropped non-terminal body-locals
  from tracking without first calling `validateExitEdge`, so a
  typestate-bearing local introduced inside a loop body that escaped
  the current iteration via `continue` (without reaching a terminal
  state and without a registered `{.destructorTransition.}`) silently
  slipped past the analyzer. The break handler already validated the
  symmetric case correctly; round-11 mirrors the same
  `validateExitEdge` call into the continue handler, using the
  edge-kind label `"continue"` (parallel to the existing `"break"` /
  `"return"` / `"raise"` / `"fall-through"` labels) so CFG-001
  diagnostics report the exit edge accurately. The terminal-accept
  and destructor-accept short-circuits inside `validateExitEdge` are
  reused unchanged, so loops whose body-locals reach terminal before
  `continue` or whose types carry a `{.destructorTransition.}`
  continue to verify cleanly. New fixtures cover the three exit-edge
  shapes:
  `cfg_analyzer_continue_drops_non_terminal_local` (rejects),
  `cfg_analyzer_continue_terminal_local` (terminal-accept), and
  `cfg_analyzer_continue_local_with_destructor` (destructor-accept).
  Closes the audit-incompleteness gap between `break` and `continue`
  exit-edge validation. No known-limitation language.
- **CFG analyzer: dead `destructorTypes` parameter removed from
  `lookupTypestateForType`.** Round-11 cleanup: the
  `lookupTypestateForType` proc accepted a `destructorTypes:
  Table[string, TypestateGraph]` parameter that was referenced in the
  docstring but never read by the proc body — graph resolution
  routes solely through `findTypestateForState` and
  `findAttachmentForType`, both of which key on the type name alone.
  The destructor table is consulted at the actual exit-edge check
  (`validateExitEdge` -> `hasDestructorFor`) and never during graph
  resolution. Removed the parameter from the signature and updated
  the single call site in `tryBindLocalFromCallInit`'s var/let-init
  path. Same cleanup pattern as round-8's `applyCallTransitions`
  `destructorTypes` removal; behavior unchanged, surface narrowed.
- **CFG analyzer: `extractTypestatedParams` captures `sink T` params
  for source-state-aware overload disambiguation at trailing positions.**
  Round-9 surfaced a parallel gap to the round-5 source-state-aware
  overload-lookup work: the helper that builds `TypestatedParam`
  entries on each registered proc matched ONLY `var T` typestate-
  bearing params (`nnkVarTy`), silently excluding `sink T`
  (`nnkCommand(sink, T)`) typestate-bearing params at trailing
  positions. `findTransitionByCalleeAndArgStates` iterates
  `typestatedParams` to apply per-position source-state constraints
  against the call-site `argStates`; with trailing sink params
  excluded from the seq, the lookup had no constraint at those
  positions and degraded to a name-only countdown that picked the
  last-registered overload regardless of trailing-arg source state.
  Two transitions sharing the same first-param source state but
  differing only in the source state of a trailing sink param (e.g.
  `combine(a: sink Open, b: sink Stage1): Mid1` vs.
  `combine(a: sink Open, b: sink Stage2): Mid2`) silently
  mis-disambiguated at every `var f = combine(...)` and
  `f = combine(...)` call site, binding the LHS to the wrong
  destination and downstream-leaking the wrongly-bound local as a
  CFG-001 false positive. Round-9 extends the helper to ALSO match
  `nnkCommand(sink, T)` and adds an `isSink: bool` field to
  `TypestatedParam`; the source-state-aware lookup naturally picks up
  the new entries via the existing `paramIndex`-based iteration. The
  `runCfgAnalyzer` pre-population step skips `isSink=true` entries so
  transition bodies that construct `result` independently of the sink
  param (the canonical `result = Dst(src.Base)` shape) continue to
  verify cleanly — sink ownership transfers in and the value dies
  with the proc frame regardless of body-side textual consumption, so
  pre-populating sink params would false-fire CFG-001 in every
  transition body. The audit matrix this round extends the param-kind
  filter audit (var T matched, sink T matched as of this round; bare
  value T, ref T, ptr T, static T, typedesc[T], and union sources are
  documented as intentional exclusions in the proc doc). New fixtures
  cover both var-init and asgn binding paths:
  `cfg_analyzer_overloaded_sink_transition_var_init` and
  `cfg_analyzer_overloaded_sink_transition_asgn`. No
  known-limitation language.
- **CFG analyzer: discard handler captures pre-walk `attachedTypeName`
  for the destructor-lookup-key fallback.** Round-9 surfaced a parallel
  gap to the round-6 destructor-lookup-key threading and round-8 branch
  reconciliation work: the discard handler's bespoke direct-table
  destructor lookup (kept inline because `hasDestructorFor`'s
  LocalTypestate signature cannot be threaded through when the operand
  walk has consumed the local) keyed `attachedKey` ONLY on the
  post-walk `result.locals[localIdx].attachedTypeName`. Intrinsic-
  consumer shapes (`discard move(m)`, `discard m.sink()`,
  `discard system.move(m)`, `discard m.move()`) consume the underlying
  tracked local inside the operand walk via
  `applyCallTransitions`'s intrinsic-arg block, so `localIdx` falls
  back to -1 at the lookup point and `attachedKey` was forced to "".
  For §3.7 attached locals, the destructor is registered against the
  OBJECT type name (not the typestate state name); with `attachedKey`
  empty the lookup fell back to `exprStateName` only, missed the
  Mailbox-keyed destructor, and CFG-003 false-fired on an attached
  local whose holder-type destructor would correctly bridge the
  moved-out temporary to terminal at scope exit. Round-9 adds a
  pre-walk capture of `attachedTypeName` (parallel to the existing
  pre-walk `name` + `stateType` capture introduced in round-5 Finding
  #3) so the destructor lookup falls back to `preWalkAttachedTypeName`
  when `localIdx == -1`. The audit matrix this round extends from
  CONSTRUCTION sites (round-6 + round-8) to USE sites — the two USE
  sites of `attachedTypeName` for destructor/diagnostic decisions are
  `hasDestructorFor` (line 317, threaded correctly since round-6) and
  this discard-handler direct-table lookup (line 1670, fixed this
  round). No other USE sites surfaced; the audit confirmed coverage.
  New fixtures cover both branches:
  `cfg_analyzer_discard_attached_type_with_destructor` (the
  destructor-covered case now compiles cleanly) and
  `cfg_analyzer_discard_attached_type_no_destructor` (the
  no-destructor case still fires CFG-003 correctly, confirming the
  round-9 fix does not weaken coverage). No known-limitation
  language.
- **CFG analyzer: `attachedTypeName` propagated through
  `reconcileBranches`.** Round-8 surfaced a parallel gap to the
  round-6 destructor-lookup-key threading: the four `LocalTypestate`
  construction sites inside `reconcileBranches` (entry-set all-same
  merge, entry-set terminal-witness preservation, branch-introduced
  all-same merge, branch-introduced terminal-witness preservation)
  built merged live-set entries WITHOUT propagating
  `attachedTypeName` from the per-branch source. Any §3.7 attached
  local that crossed a branch reconciliation surfaced downstream
  with `attachedTypeName=""`, so the destructor lookup at the next
  exit edge fell back to `stateType`, missed the registered
  `=destroy` on the holder type, and false-fired CFG-001 on
  destructor-covered attached locals after the merge. Same class as
  round-6 (which threaded the field through var-init, asgn-rebind,
  in-place advancement, and live-set pre-pop) — round-8 extends the
  audit matrix from destructor-lookup-key sites to ALL
  `LocalTypestate` construction sites in `verify.nim`. The matrix
  re-run confirmed only the four `reconcileBranches` sites were
  missing the propagation; the call-init fresh-bind (line 1049) and
  asgn fresh-bind (line 1780) intentionally start with
  `attachedTypeName=""` because call-init / asgn produce state-typed
  bindings whose LHS has no prior holder-type lineage. Also removes
  an unused `destructorTypes` parameter from `applyCallTransitions`
  identified by the same round-8 review pass — the proc body never
  read the table, so the parameter was dead weight on all five call
  sites and tripped a -Wunused-parameter equivalent on the
  signature. New fixtures cover both the entry-set and
  branch-introduced merge sites with and without destructor
  coverage:
  `cfg_analyzer_attached_branch_entry_local_drops_link` (CFG-001
  fires under the attachedTypeName-keyed lookup miss when no
  destructor is registered),
  `cfg_analyzer_attached_branch_entry_local_destructor` (the
  attached-type destructor hit survives the entry-set merge),
  `cfg_analyzer_attached_branch_introduced_local_drops_link` (same
  shape for the second-pass branch-introduced merge), and
  `cfg_analyzer_attached_branch_introduced_local_destructor` (the
  positive path for the second-pass merge). No known-limitation
  language.
- **CFG analyzer: `extractTrackedLocal` recognises dot-call intrinsic
  consumers in `nnkCall` / `nnkCommand`.** Round-7 closed the
  remaining coverage gap in the helper's intrinsic-consumer branch:
  pre-fix the gate `n.len == 2 and isIntrinsicConsumer(n[0])` only
  matched the prefix shape `move(f)` / `system.move(f)` (which carry
  the consumed arg at `n[1]`) and returned `none(string)` for the
  method-call sugar shape `f.move()` (parsed as
  `nnkCall(nnkDotExpr(f, move))` with `n.len == 1` and the callee
  itself the DotExpr). The false-negative left the underlying tracked
  local invisible to two downstream consumers: (1)
  `buildArgStatesFromCall`'s per-arg resolution, so a registered
  transition called as `close(f.move())` could not disambiguate its
  arg's source-state against the underlying local `f`, leaving `f`
  tracked at its pre-call state through the fall-through edge and
  false-firing CFG-001 on the canonical Nim ownership-transfer
  idiom; and (2) the discard handler's pre-walk capture, so `discard
  f.move()` of a non-terminal local with no covering destructor
  silently bypassed CFG-003 (the operand walk's intrinsic-arg drop
  hid the violation because no pre-walk state was captured to
  validate against). Post-fix the helper delegates to
  `intrinsicConsumerArg`, which uniformly handles prefix,
  qualified-prefix, AND dot-call shapes — yielding the consumed
  argument position for every recognised callee, and `nil` (→
  `none(string)`) for non-intrinsic calls, preserving the pre-fix
  behaviour for that branch. Same class as round-5 Finding #2 which
  unified `isIntrinsicConsumer` to recognise the dot-call callee
  shape; round-7 extends that unification to the helper that resolves
  the consumed-argument position downstream. New fixtures cover both
  effects: `cfg_analyzer_dot_call_intrinsic_as_call_arg` (positive —
  `close(src.move())` inside a transition body resolves `src` and
  reaches terminal cleanly) and
  `cfg_analyzer_discard_dot_call_intrinsic_non_terminal` (negative —
  `discard f.move()` on a
  non-terminal local with no destructor fires CFG-003 as expected).
  No known-limitation language.
- **CFG analyzer: §3.7 typestate-attachment threaded through the
  destructor-lookup data model.** Round-6 surfaced a single coherent
  integration gap: the §3.7 typestate-attachment pragma (introduced
  earlier in 0.9.0) was never plumbed into the analyzer's
  `LocalTypestate` / `TypestatedParam` data model. Destructors for
  attached object types are registered against the OBJECT type name,
  not the typestate state name, so the analyzer's
  `stateType`-keyed destructor lookup silently missed every
  `=destroy` declared with `{.destructorTransition.}` on an attached
  holder type, false-firing CFG-001 at every exit edge for attached
  locals and params that were correctly covered by a destructor.
  Round-6 extends `TypestatedParam` and `LocalTypestate` with a new
  `attachedTypeName: string` field (empty for state-typed locals and
  params — path (a) — preserving the pre-round-6 behaviour exactly
  for non-attached typestate machines). `hasDestructorFor` now keys
  on `attachedTypeName` first when set and falls back to
  `stateType`, with both paths still requiring the resolved
  destructor's owning typestate graph to match the local's graph so
  same-state-name collisions across distinct typestates do not
  satisfy each other. `extractTypestatedParams` (pragmas.nim)
  resolves the param's `stateType` to the attachment's
  `initialState` (not the object type name, which is not itself a
  registered state) and captures the object type name into
  `attachedTypeName`. `bindLocalsFromIdentDefs` (var-init), the asgn
  rebind path, the in-place advancement inside
  `applyCallTransitions`, the discard-handler's destructor probe in
  `walkCfg`, and the proc-entry pre-population from
  `proc.typestatedParams` all propagate `attachedTypeName` through
  every `LocalTypestate` construction site so the field survives
  state advancement, rebind, and live-set pre-pop. A destructor-
  lookup-key audit matrix (every callsite × {attached-with-
  destructor, attached-without-destructor, non-attached-with-
  destructor, non-attached-without-destructor}) confirmed the
  state-typed fallback path remains intact for non-attached
  typestate machines and no additional gaps surfaced. New fixtures
  cover each finding's positive and negative regression: attached
  local non-terminal at scope (CFG-001 fires using the
  attachedTypeName-keyed lookup); attached local with
  destructorTransition reaches terminal cleanly via the destructor
  hit; attached param transitioned mid-body and consumed at exit
  (live-set pre-pop preserves the field across transitions);
  attached asgn-rebind regression (rebind keeps the field, so
  destructor lookup still hits after the first transition); and a
  mixed proc taking both attached and state-typed params confirming
  the fallback path still hits non-attached destructors. No
  known-limitation language.
- **CFG analyzer: source-state-aware overload lookup correctly indexes
  through mixed typestate / non-typestate parameters.** Round-4
  introduced `findTransitionByCalleeAndArgStates` with a loop that
  iterated `argStates` (call-site arg positions, length = call arg
  count) and indexed into `p.typestatedParams` (compacted
  typestate-bearing-only entries, length ≤ call arg count) with the
  same loop variable. When a registered transition mixed
  typestate-bearing `var T` params with non-typestate params at
  intervening positions, the trailing typestate-bearing arg's
  call-site position was beyond `typestatedParams.len`, tripping the
  out-of-bounds guard and falsely rejecting the proc. Round-5
  captures each `TypestatedParam`'s 0-based proc-parameter position
  (new field `paramIndex`) at registration time, and the lookup
  iterates the compacted `typestatedParams` seq, indexing back into
  `argStates` via `paramIndex`. The first-position param's
  source-state constraint remains handled by the existing
  `p.sourceState` check; the loop now correctly disambiguates
  overloads across mixed-param signatures like
  `proc mt(a: sink Open, n: int, b: var Open): HalfOpen`.
- **CFG analyzer: `isIntrinsicConsumer` recognises dot-call method
  form `f.move()`.** Round-3 added prefix `move(f)` / `sink(f)` and
  qualified `system.move(f)` / `system.sink(f)` recognition. The
  method-call sugar form `f.move()` (parsed as
  `nnkCall(nnkDotExpr(receiver, methodIdent))` where the receiver IS
  the consumed value) was missed: library code using pipe-style
  intrinsic consumption left the underlying tracked local on the
  live-set and false-fired CFG-001 at fall-through (or asgn-binding
  loss for the asgn-RHS variant). Round-5 extends the recognizer to
  accept any `nnkDotExpr` whose trailing identifier is `move` or
  `sink`. A companion helper `intrinsicConsumerArg(call)`
  disambiguates the consumed-argument position: for the
  `system.X(f)` qualified-prefix shape the arg is `call[1]`; for the
  `f.X()` method-call shape the arg is the receiver `call[0][0]`.
  All call sites (the `applyCallTransitions` intrinsic block, the
  discard handler, the asgn handler) route through the unified
  helper so the shape discrimination lives in one place. Note: the
  parser does not accept `f.sink()` as a method call (`sink` is a
  reserved type modifier in Nim), so only `f.move()` is exercisable
  via dot-call sugar; qualified `system.sink(f)` and prefix
  `sink(f)` continue to be recognised symmetrically.
- **CFG analyzer: `discard move(f)` no longer bypasses CFG-003 on
  non-terminal locals.** The discard handler's pre-round-5
  intrinsic-callee short-circuit (`isIntrinsicConsumer(opnd[0])` ->
  drop local + return) ran BEFORE the CFG-003 non-terminal-discard
  check, allowing `discard move(f)` where `f` was at a non-terminal
  state with no `{.destructorTransition.}` to silently pass. The
  short-circuit was also redundant: the operand recursion through
  `walkCfg` -> `applyCallTransitions` already handled the intrinsic
  consumption via its own intrinsic-consumer block. Round-5 removes
  the redundant short-circuit and adds a pre-walk state capture so
  the CFG-003 check observes the discarded value's pre-discard
  state — if the underlying local was at a non-terminal state with
  no covering destructor, the discard fires CFG-003 naming the
  state and the typestate. Existing `discard move(f)` patterns in
  `{.notATransition.}` wrappers (which the analyzer does not visit)
  are unaffected; transition-proc-body patterns that previously
  bypassed CFG-003 silently now correctly fire the diagnostic. The
  `discard_move_unrelated_local_leaks` should_fail fixture was
  updated to isolate its CFG-001 intent from this CFG-003 closure
  by giving the moved local a registered destructor.
- **CFG analyzer: asgn and var-init binding paths strip transparent
  AST wrappers before the kind check.** Pre-round-5 the asgn
  handler (and `bindLocalsFromIdentDefs` var-init path) keyed off
  `rhs.kind in {nnkCall, nnkCommand}` directly. The Nim parser
  wraps several structurally-transparent shapes around expressions:
  `nnkPar(x)` (parenthesised single expression, e.g. `f = (open())`),
  `nnkStmtListExpr(..., x)` (statement-list-as-expression whose last
  child is the value, e.g. `f = (let _ = setup(); open())`), and
  `nnkBlockStmt(name, body)` / `nnkBlockExpr(name, body)` (block-
  as-expression, e.g. `f = block: open()`). All three slipped past
  the kind check to the else-branch which recursed into children
  (applying nested call effects via `walkCfg`) but never invoked
  the LHS binding-recovery path, so `f` lost its tracked state on
  rebinding from a wrapped registered-transition call. Round-5
  introduces `stripTransparentExprWrappers(n)` which descends to
  the underlying value-producing node (recursively, so
  `((open()))` and `block: (open())` both reduce), and the asgn
  and var-init paths apply it before the kind check. The same
  helper-coverage audit extended `extractTrackedLocal` to handle
  multi-statement `nnkStmtListExpr` (last expression) and
  `nnkBlockStmt` / `nnkBlockExpr` (body's last expression) shapes,
  so every tracked-local extraction site benefits from the
  expanded wrapper coverage uniformly.
- **CFG analyzer: unified AST-traversal pattern matching.** Introduced
  `extractTrackedLocal(n: NimNode): Option[string]` and
  `isIntrinsicConsumer(callee: NimNode): bool` helpers in
  `src/typestates/verify.nim`. Every AST-traversal site in the analyzer
  (call-argument iteration, conversion-consume subtree walk, discard
  operand resolution, asgn RHS handling, and conversion-consume receiver
  routing for dot-call shapes) now routes through these helpers,
  eliminating per-site pattern coverage gaps. The helpers recognise
  `nnkIdent` / `nnkSym` direct references, `nnkDotExpr` receivers
  (`f.Base`, `obj.field.subfield`), `nnkCommand` and `nnkCall` wrappers
  around `move` / `sink` / `system.move` / `system.sink` symmetrically,
  `nnkConv` explicit conversions, and arbitrary recursive compositions
  (`close(move(f.Base))`, `Closed(move(c).Buffer)`, `src.Dst()`,
  `discard move(f)`, `x = move(f)`). Closes the pattern-coverage class
  of false-positive / false-negative bugs surfaced across the
  round-1 / round-2 / round-3 review iterations: the conversion-consume
  path is no longer dot-call-blind, the move/sink unwrap is no longer
  `nnkCall`-blind, and intrinsic-callee consumption shapes are
  recognised in both `discard` and `asgn` positions.
- **CFG analyzer recognizes method-call (dot-call) shapes.** The
  analyzer now treats the receiver `call[0][0]` of an
  `nnkCall`/`nnkCommand` with an `nnkDotExpr` head as the implicit first
  argument (parameter position 0) of the underlying proc. Pre-fix the
  per-call iteration walked only `call[1..N-1]`, missing the receiver
  entirely and false-firing CFG-001 on idiomatic `f.close()` /
  `f.transition()` / chained dot-call patterns. Prefix-call shape
  (`close(f)`) was unaffected and remains the same code path.
- **CFG analyzer pre-populates `var T` typestate-bearing params.** At
  proc entry the analyzer now seeds `LiveState` with one local per
  `var T` typestate-bearing formal parameter, captured at registration
  time into the new `RegisteredProc.typestatedParams` field. Pre-fix the
  live-set was empty at proc entry, so a proc that took
  `var f: File[Open]` and returned early without consuming `f` silently
  passed analysis. Sink-typed and value-typed params are NOT
  pre-populated: their values die with the proc frame regardless of
  whether the body textually references them (the proc's signature
  itself encodes the transition Src -> Dst). The analyzer also now
  recognizes the canonical conversion-consume idiom `Dst(src.Base)`,
  dropping a tracked local from the live-set when it appears inside a
  type-conversion call whose callee is a registered state-type ident.
- **CFG analyzer validates branch-introduced locals at scope-exit.**
  `reconcileBranches` now validates every branch-local declared inside a
  single branch (absent from the entry-set AND absent from at least one
  other branch) reaches a terminal state — or has a registered
  `{.destructorTransition.}` — before the branch closes. Pre-fix these
  branch-locals were silently dropped from the merged live-set,
  escaping CFG-001 validation entirely: a `var f = open()` inside an
  `if` branch with no consumption and no destructor produced a clean
  compile when it should have flagged a leak. The new check fires at
  branch-close with a CFG-001-shaped diagnostic naming the local and
  its non-terminal state. Destructor short-circuit mirrors
  `validateExitEdge`'s existing rule for `{.destructorTransition.}`
  types: Nim's `=destroy` injection fires at branch-close, so a
  destructor-backed branch-local is accepted without explicit
  consumption.
- **CFG analyzer var-init and asgn binding paths use source-state-aware
  overload lookup.** A new helper `findTransitionByCalleeAndArgStates`
  (and supporting `buildArgStatesFromCall`) replaces the name-only
  countdown loops at the var-init site (`tryBindLocalFromCallInit`,
  `verify.nim:625`) and the asgn binding site (`verify.nim:1172`).
  Pre-fix both sites picked the LAST registered overload by callee
  name regardless of the call-site arg's source-state — so a proc
  registered with multiple overloads disambiguated by source-state
  (e.g., `tx: File[Closed] -> File[Open]` and
  `tx: File[Errored] -> File[Open]`) would mis-bind the LHS to
  whichever overload happened to appear last. The new helper filters
  candidates by both callee-name AND each tracked-local arg's
  source-state, picking the matching overload deterministically.
  Composes with the call-site source-state-aware lookup that already
  existed in `applyCallTransitions` via `findRegisteredTransitionForArg`
  (round-1). When the call-site has no tracked-local args, the helper
  degrades to name-only matching, preserving the pre-round-4 behavior
  for call sites that cannot supply source-state information.
- **CFG analyzer scoped to caller's module.** `verifyTypestates()` is
  now a template that captures the caller's absolute module path via
  `instantiationInfo(-1, fullPaths = true)` and forwards it to
  `verifyTypestatesImpl`. The implementation macro filters
  `registeredProcs` to entries whose `modulePath` matches the caller,
  applying that filter to the strictTransitions/external-proc check,
  the F5 decoy emission, and `runCfgAnalyzer`. Pre-fix every module's
  `verifyTypestates()` call re-walked every accumulated proc body from
  every imported module — O(N^2) compile-time cost across a project.
  Cross-module call-graph analysis remains a future enhancement;
  v0.9.0 analyzes the caller's module only. Legacy callers (e.g.
  CLI tooling) that invoke `runCfgAnalyzer()` directly with an empty
  `callerModulePath` continue to walk every registered proc.
- Declare `chronos` and `results` as test-only dependencies via
  `taskRequires "test", ...` in `typestates.nimble`. Previously, tests in
  `tests/should_compile/transitions/async_*` and
  `tests/should_compile/transitions/wrapper_result_*` failed to compile
  because their `chronos` / `results` imports were not resolved on a fresh
  `nimble test`. Production installs unaffected.

### Internal

- New `pkDestructorTransition` value on the `ProcKind` enum; new fields
  on `RegisteredProc`: `body*: NimNode`, `skipCfg*: bool`,
  `attachedObjectTypeName*: Option[string]`,
  `typestatedParams*: seq[TypestatedParam]`. New public type
  `TypestatedParam*` (name + stateType + graphName) captures
  typestate-bearing `var T` formal parameters at registration time so
  the CFG analyzer can pre-populate the live-set at proc entry.
- `verifyTypestates*` is now a template that captures the caller's
  module path via `instantiationInfo(-1, fullPaths = true)` and forwards
  it to a new `verifyTypestatesImpl*(callerFile: static[string])` macro,
  which scopes its per-proc scans to the caller's module. `runCfgAnalyzer*`
  gains an optional `callerModulePath` parameter (defaults to empty,
  preserving the all-procs behavior for direct callers).
- `destructorTransitionCore` shared implementation for both arities of
  `destructorTransition` (`src/typestates/pragmas.nim`).
- Extract `peelNameWrappers` and `accQuotedToStr` compile-time helpers in
  `src/typestates/pragmas.nim`. Consolidates the `nnkPragmaExpr` →
  `nnkPostfix` name-wrapper peel and the `nnkAccQuoted` ident-reassembly
  loop previously duplicated across `extractTypestatedParams`,
  `destructorTransitionCore`, and `extractTypeDeclName`. Behaviour
  preserved — same fixtures, same test pass count.
- CFG analyzer pass integrated into `verifyTypestates*`
  (`src/typestates/verify.nim`), running after the unmarked-proc check
  and the F5 decoy pass.
- `generateAttachmentMarker` codegen helper emits a guarded
  per-typestate attachment macro plus the same-name fallback warning.
- Drop the unreachable sentinel `""` from `buildSingleTargetMatchCase`'s
  state-name `case` expression. `error` from `std/macros` aborts compilation,
  so the case type-checks as `string` from the three matching branches alone;
  the sentinel only added an `UnreachableCode` compiler warning visible
  during `nimble test`.
- Tighten `.gitignore` rule for nested test binaries. The prior pattern
  `tests/**/[a-z_]*/` (directory-level) excluded category subdirs like
  `tests/should_compile/transitions/`, which prevented re-including new
  `.nim` sources via `!tests/**/*.nim` (git forbids re-including files
  under an ignored parent). New file-level patterns target binaries one
  level below `should_*` without matching the category dirs themselves,
  so new test sources can be added without `git add -f`.

## [0.8.0] - 2026-05-07

### Added

- **Generated `match` macro per single-target state.** Every state in a
  typestate graph now emits a `match` macro overload alongside the
  existing per-branching-union overloads (introduced in v0.5.0). Callers
  can use identical `StateName(bind):` syntax whether the matched value
  is a branching union (e.g. `ProcessResult`) or a bare single-target
  state (e.g. `Approved` returned by `proc approve(c: sink Created): Approved {.transition.}`).
  The single-target `match` rewrites `match v: State(b): body` into
  `block: var valTmp = v; let b = move(valTmp); body` (call-expression
  value sources) or `block: let b = move(v); body` (l-value identifier
  sources), so the source expression is evaluated exactly once. The
  generated macros are disambiguated by Nim on the typed first
  parameter, so single-target and branching `match` coexist for the
  same state name when that state is reachable both as a branching arm
  (e.g. via `as Decision`) and as a bare return.

### Changed

- **BREAKING (DSL-level only):** Branch wrapper type names declared via
  `as TypeName` may no longer collide with any state name in the same
  typestate. Previously such a collision was syntactically accepted but
  would produce duplicate `type` definitions; with the new single-target
  `match` codegen it would also produce two `match*(value: <Name>; ...)`
  overloads with the same first-param type. The parser now errors
  before codegen with a message naming the offending wrapper and
  suggesting a distinct name (e.g., `ApprovedResult`). No existing
  in-tree typestate tripped this validation; downstream users with a
  collision must rename the wrapper.

### Internal

- New helper `buildSingleTargetMatchCase*(value, arms, validStateName)`
  in `src/typestates/codegen.nim`, paralleling `buildMatchCase`. Wraps
  the rewritten arm in a `block:` so adjacent matches that bind the
  same name do not collide, and uses a gensym'd `var valTmp` temporary
  for call-expression sources to satisfy `system.move`'s `var T`
  requirement while ensuring exactly-once evaluation.
- New generator `generateSingleTargetMatch*(graph)` emits one `match`
  macro per state in `graph.states`. Wired into `generateAll` after
  `generateBranchMatch`.
- New post-parse validator `validateNoBranchTypeStateCollision` in
  `src/typestates/parser.nim`, called from `parseTypestateBody`
  alongside the existing post-parse validators.
- Ten new test files under `tests/should_compile/transitions/` (six)
  and `tests/should_fail/transitions/` (four) cover: basic match,
  generic-context match, empty-object state, call-expr value source
  with side-effect-count assertion, two adjacent matches binding the
  same name, a state used in both branching and single-target paths,
  wrong-state arm, multi-arm, zero-arm, and the wrapper/state
  collision parser error.

## [0.7.2] - 2026-05-04

### Fixed

- `match` macro now expands correctly when invoked from a generic proc body whose call site does not directly import the kind enum module. The generated macro previously emitted bare `ident(prefix & stateName)` nodes for the `case` arms (e.g. `oOk`, `pApproved`); those idents had to resolve at the consumer's call site, which failed with `Error: undeclared identifier: '<field>'` when the consumer reached the typestate only through a facade that did not re-export the kind enum. The macro now pre-resolves each kind-enum field via `bindSym` at typestate-decl time (where the enum is in scope) and threads the resolved syms into `buildMatchCase`, so consumer-site visibility is no longer required.

### Internal

- `buildMatchCase` signature changed from `(value, arms, prefix: string, validNames: seq[string])` to `(value, arms, validNames: seq[string], kindSyms: seq[NimNode])`. The proc is documented internal-only and called solely from generated `match` macros, so no public API contract is broken.
- New regression test `tests/should_compile/transitions/match_external_consumer.nim` plus fixtures `tests/fixtures/match_consumer_lib.nim` and `tests/fixtures/match_consumer_wrapper.nim` exercise the three-module facade pattern: typestate-defining module, wrapper that imports but does not re-export it, and consumer that only sees the wrapper.

## [0.7.1] - 2026-05-02

### Fixed

- `match` macro now works in generic call sites (`proc[T]` / `template[T]` bodies). Previously, sema converted the arm-head identifier to `nnkSym` or `nnkOpenSymChoice` before the macro expanded, and `buildMatchCase` rejected those node kinds with "match arm head must be a single state identifier". The check now accepts `nnkIdent`, `nnkSym`, `nnkOpenSymChoice`, and `nnkClosedSymChoice` arm heads.

### Documentation

- `docs/guide/cli.md` now documents the v0.7 verify flags (`--warnings-as-errors` / `-W`, `--format=<default|github|json>`), describes the parse-error fail-soft behavior, and points to `ci-integration.md` for full coverage instead of duplicating CI examples.
- `docs/guide/verification.md` mentions the v0.7 flags with cross-links to `cli.md` and `ci-integration.md`.
- `docs/guide/ci-integration.md` adds a note on the parse-error fail-soft behavior (one bad file no longer aborts the rest of the batch).

## [0.7.0] - 2026-05-02

### Added

- New `--warnings-as-errors` flag (short alias `-W`) on `typestates verify`: promotes any warning to a non-zero exit, gating CI on lint warnings.
- New `--format=<default|github|json>` flag on `typestates verify`:
  - `github`: emits GitHub Actions annotation format (`::warning file=PATH,line=N::MESSAGE`) for inline PR review comments.
  - `json`: emits a documented stable schema with `schemaVersion: 1` envelope. See [CI Integration](docs/guide/ci-integration.md) for the schema spec.
- New `.pre-commit-hooks.yaml` hook manifest at repo root. Other repos can consume it by referencing `repo: https://github.com/elijahr/nim-typestates` in their `.pre-commit-config.yaml`.
- New documentation: [CI Integration](docs/guide/ci-integration.md) covers pre-commit, GitHub Actions, GitLab CI, treating warnings as errors, inline annotations, and the JSON schema.
- New stable code taxonomy for findings: `file-not-found`, `parse-error`, `unmarked-proc-strict`, `unmarked-proc`, `unreachable-state`, `non-terminal-state`, `orphan-state`, `no-entry-point`, `opaque-state-bypass`, `opaque-states-no-initials`. Codes are stable within a major version; documented stability policy in [CI Integration](docs/guide/ci-integration.md).
- `Finding.column: int` field captures column numbers from parser diagnostics. Surfaced as `column` in JSON output and as `col=N` in GitHub annotations when non-zero.

### Changed

- **BREAKING:** `VerifyResult.errors` and `VerifyResult.warnings` are now `seq[Finding]` instead of `seq[string]`. The new `Finding` record carries `path`, `line`, `severity`, `code`, `message`, and `hint` fields. Tests asserting on warning/error substrings should match against `it.message` (or `it.hint` for diagnostic hints from reachability findings). See [CI Integration](docs/guide/ci-integration.md) for the full schema.
- Reachability warnings (rfDead, rfTrap, rfOrphan, rfNoEntryPoint) now split message and hint into separate fields. The default human-readable output is unchanged from v0.6.
- ParseError on input files now routes through the Finding pipeline as a `parse-error` code. Under `--format=github` and `--format=json`, parse failures produce annotation/JSON output rather than plain stderr text. A parse error in one file no longer aborts verification of the rest of the batch — every problem surfaces in a single run.

### Internal

- New module `src/typestates/findings.nim` containing `Finding`, `Severity`, `FindingCode`, helpers (`mkError`, `mkWarning`), and formatters (`formatHuman`, `formatGitHub`, `formatJson`).
- All warning/error emission sites in `cli.nim`, `reachability.nim`, and `lint_opaque_states.nim` migrated to construct `Finding` records.
- `.gitignore` whitelists `tests/fixtures/**` and common non-Nim file types under `src/typestates/`. Preventive against future fixture additions being silently ignored.
- New tests: `tcli_verify_formats.nim`, `tcli_warnings_as_errors.nim`, `tcli_parse_error.nim`, `tcli_gitignore.nim`. Existing tests `tcli.nim`, `tcli_verify_warnings.nim`, `tcli_opaque_states.nim`, `tlint_opaque_states.nim` migrated to the Finding API.

## [0.6.0] - 2026-04-30

### Added

- `opaqueStates = true` opt-in flag for typestate declarations. Enables a CLI-side lint that emits warnings when raw distinct casts construct non-initial states outside `{.transition.}` procs. See [Cast Protection guide](docs/guide/cast-protection.md) for caught/missed surface and known limitations. Warnings only; no compile-time enforcement.

### Internal

- New module `src/typestates/lint_opaque_states.nim`.
- New public proc `parsePNode` in `ast_parser` (extracted from `parseFileWithAst` to share parser-init code with the lint).

## [0.5.0] - 2026-05-01

### Added

- **Auto-generated `$` overload for typestate values.** Each leaf state type
  and the generated state enum now have a `$` proc returning the bare state
  name (no `fs` prefix). Under the default `consumeOnTransition = true`, calling
  `$` on a value will consume it; the docs call out this interaction and the
  workaround (`$state(value)`).
- **Reachability and liveness warnings.** New `initial:` and `terminal:` DSL
  blocks let the parser flag unreachable states and dead-end (non-terminal)
  states at compile time. The `typestates verify` CLI surfaces the same
  warnings on `.nim` files without rebuilding.
- **Generated `match` macro per branching union.** Every `as TypeName` branch
  type now emits a `match` macro that dispatches on the variant kind with
  compile-time exhaustiveness checking. The matched value must be `var`
  (branch fields are extracted with `move`), arms use `StateName(bind):`
  syntax, and missing or unknown branches error at the call site.
- **State-aware error messages on transition misuse.** When a module calls
  `verifyTypestates()`, every non-generic, non-branching `{.transition.}` proc
  now also emits `{.error.}` decoy overloads for the other states in its
  typestate, with consistent extra parameters across overloads (an
  `anySkipped`-style flag keeps the decoy and live signatures shaped
  identically). Calling a transition with the wrong source state surfaces a
  tailored message naming the proc, the wrong state, and the expected source,
  instead of Nim's generic "type mismatch" diagnostic. Generic typestates and
  branching-return procs are skipped in v0.5 and tracked as a v0.6 follow-up.

### Fixed

- **README payment example compiles under default `consumeOnTransition`.**
  Transition procs in the README now take `sink` parameters, the async
  section was corrected, and a regression fixture covers the example.

## [0.4.1] - 2026-04-30

### Fixed

- **CLI `--version` reported the wrong version.** `typestates --version`
  printed `typestates 0.3.0` regardless of the installed package version
  because the string was hardcoded in `showVersion()`. The CLI now derives
  the version from `NimblePkgVersion` at build time, keeping the package
  version (`typestates.nimble`) as the single source of truth. The
  `buildCli` task forwards the version through `-d:NimblePkgVersion=` so
  developer builds match `nimble install` output.

### Documentation

- README rewritten for clarity. Tightened prose, replaced the Key Features
  table with a flat list, added a Cross-Type Bridges example, surfaced the
  Nim < 2.2.8 codegen workaround inline, and trimmed the documentation
  link list to point readers at the docs site for the long tail.

## [0.4.0] - 2026-04-23

### Added

- **Transparent-wrapper unwrapping for transition return types.**
  `{.transition.}` now looks through transparent wrappers (built-in:
  `Result`, `Option`, `Future`) to find the destination state. Procs
  like `proc f(s: A): Result[B, E] {.transition.}` and
  `proc g(s: A): Option[B] {.transition.}` validate the underlying
  A → B edge transparently.
- **Async/Future return-type validation.** `{.async, transition.}`
  procs returning `Future[T]`, `Future[Result[T, E]]`, or any
  combination of registered transparent wrappers now validate the
  underlying destination state. Pragma order is interchangeable;
  `{.transition, async.}` is recommended for forward-compat with
  future body-level analysis.
- New public API for transparent-wrapper management:
    - `{.transparentWrapper.}` marker pragma (cosmetic; the wrapped
      state type must be the wrapper's first generic argument)
    - `registerTransparentWrapper(name: string)` — register a wrapper
      type (base or module-qualified name) at `static:` time
    - `unregisterTransparentWrapper(name: string)` — opt out of a
      built-in or previously-registered wrapper
    - `isTransparentWrapper(name: string): bool` — predicate
- Test runner extension: `tests/tcomprehensive_runner.nim` now
  supports `# expects: "<substring>"` directives in `should_fail/`
  test files. The runner AND-checks each substring against captured
  compiler output. Backward-compatible (existing tests unaffected).
- Direct test coverage for the Nim issue #25341 codegen-bug gate:
    - `tests/should_fail/consume/codegen_bug_gate.nim` exercises
      the live gate on Nim < 2.2.8 and emits an equivalent diagnostic
      on Nim >= 2.2.8 to remain green on both.
    - `tests/should_compile/consume/codegen_bug_clean.nim` proves
      the gated typestate shape compiles cleanly on Nim >= 2.2.8.
  Together these tests verify the version triple gate is empirically
  correct against the upstream multi-file repro on both Nim 2.2.6
  (gate must fire) and Nim 2.2.8 (gate must be silent).

### Fixed

- **Union source parameters on transition procs.** `{.transition.}`
  now accepts union source parameters like `Open | PartiallyFilled`.
  Per-source diagnostics name the specific failing source state.
  Implemented via a new `extractAllSourceTypeNames` proc that mirrors
  the existing return-side union-type recursion.
- `extractAllSourceTypeNames` strips parameter modifiers
  (`sink`, `var`, `ref`, `ptr`) and explicit parentheses
  (`nnkPar` / `nnkTupleConstr`) before splitting on the union operator,
  so `sink (A | B)`, `var (A | B)`, and `(A | B)` all behave like
  `A | B` instead of falling through to the leaf fallback as a single
  opaque string.
- `extractAllTypeNames` peels single-element parenthesis wrappers ahead
  of the union case, so a parenthesized union inside a transparent
  wrapper (e.g., `Result[(A | B), E]`) matches each branch against the
  transition graph rather than the literal `"(A | B)"`.
- `extractAllTypeNames` also peels `ref` / `ptr` / `var` / `sink`
  modifiers on return types, so `proc f(a: A): ref B` validates
  `A -> B` instead of reporting "Undeclared transition: A -> ref B".
- `extractTypeName` on an `nnkBracketExpr` no longer crashes on a
  module-qualified head (`mymod.State[T]`). The head is delegated back
  to `extractTypeName`, which routes `DotExpr` through `node.repr`
  instead of a missing `.strVal`.
- The source-type extractor uses `nnkIdentDefs[^2]` instead of `[1]`,
  so transitions with grouped parameter idents (e.g.,
  `proc m(a, b: State)`) correctly identify the type node rather than
  reporting a confusing "<second-ident-name> is not part of any
  registered typestate" error.
- The single-source fallback in `extractAllSourceTypeNames` now uses
  the stripped node, so a lone parenthesized source like `(A)`
  resolves to `A` and matches the graph.
- `unwrapTransparent` bails out when an `nnkBracketExpr` has fewer than
  two children, avoiding an out-of-bounds access on macro-generated or
  malformed empty-arg wrappers.

### Behavior notes

- Users with a project-local generic type named `Result` used as a
  typestate state (rather than an error wrapper) should call
  `static: unregisterTransparentWrapper("Result")` near the typestate
  declaration to opt out of the built-in unwrap.
- Combining `{.async, transition.}` with `consumeOnTransition = true`
  may hit a chronos `Future.complete` by-value issue (chronos
  limitation, not nim-typestates). Mitigation: set
  `consumeOnTransition = false` for the affected typestate, or use
  `sink` parameter modifier explicitly.
- Recommended pragma order is `{.transition, async.}` (both orderings
  work for signature validation; transition-first is forward-compat
  with future body-level analysis).
- Registered transparent wrappers must put the wrapped state type at
  the first generic-argument position (`Wrapper[State, ...]`). This
  matches the built-in seeds (`Result[T, E]`, `Option[T]`, `Future[T]`).
  Wrappers that put the state elsewhere should NOT be registered.

### Known limitations

- Wrapper-name registry uses string-based matching against bare or
  module-qualified names. A user defining their own `Result` type in
  a project would silently get unwrapped. Use
  `unregisterTransparentWrapper("Result")` to opt out, or a different
  name that doesn't collide with the built-in seeds.

### Tooling

- Pre-commit hook configured for `nph` formatting; CI now runs a
  dedicated lint job alongside the test matrix.
- CI test matrix pinned to Nim `2.2.0` (minimum supported) and `2.2.8`
  (boundary version with the Nim issue #25341 fix). Avoids silent
  drift from `stable`.
- Replaced the broken `asdf-vm/actions/setup` chain with
  `jiro4989/setup-nim-action@v2`; added explicit installation of
  `results` and `chronos` test dependencies.
- `mkdocstrings-nim` updated to v0.2.1.

### Documentation

- New guide page: [Transparent Wrappers](docs/guide/transparent-wrappers.md)
  covers `Result` / `Option` / `Future` return-type unwrapping, custom
  wrapper registration, the first-generic-argument contract, and the
  opt-out path.
- DSL reference documents union source parameters and links to the
  transparent-wrappers page under `{.transition.}`.
- Error-handling guide documents direct `Result[State, E]` and
  `Future[Result[State, E]]` returns as alternatives to branch types.
- README and landing page list the new features.

## [0.3.1] - 2025-12-12

### Fixed

- CLI parser now correctly handles generic typestates (e.g., `EpochGuardContext[MaxThreads]`)
  - Added `nkBracketExpr` handling in AST parser for generic state names
  - Generic states now appear correctly in DOT visualization output
- DOT output now quotes identifiers containing brackets or other special characters
  - Fixes Graphviz syntax errors with generic states like `Unpinned[MaxThreads]`

## [0.3.0] - 2025-12-12

### Added

- `codegen` CLI command to output generated helper code
  - Shows the state enum, union type, state procs, and branch types
  - Useful for understanding what the macro generates
  - Usage: `typestates codegen src/myfile.nim`
- Module-qualified bridge syntax (`module.Typestate.State`) for cross-module bridges
  - Enables explicit documentation of which module a bridge target comes from
  - Module qualifiers are metadata for documentation and visualization
  - Validation uses base names for flexibility
- Automatic constraint inference for generic typestates
  - Unconstrained generic parameters (e.g., `[N]`) are automatically inferred from state type definitions
  - Reduces boilerplate when state types already declare constraints
- Library Modularity guide documenting typestate composition patterns
  - Shows how libraries can expose typestates for external consumption
  - Uses nim-debra as a case study
- Comprehensive test coverage for module-qualified bridges
  - Generic typestates with module-qualified bridges
  - Branching transitions with module-qualified bridges
  - Visualization output verification

### Fixed

- DOT generation now properly quotes bridge destinations containing dots
  - Fixes Graphviz syntax errors with module-qualified names like `module.Type.State`
- DOT unified graph now uses `fullDestRepr` for complete bridge destination names
- Improved error messages for codegen bug detection

### Documentation

- Added module-qualified syntax to bridges guide and DSL reference
- Added all guide sections to README documentation links

## [0.2.1] - 2025-12-07

### Added

- Compile-time detection of Nim codegen bug ([nim-lang/Nim#25341](https://github.com/nim-lang/Nim/issues/25341))
  - Affects `static` generic parameters with ARC/ORC/AtomicARC on Nim < 2.2.8
  - Shows clear error message with four workaround options
  - Regular generics (`Container[T]`) are not affected
- `inheritsFromRootObj` flag to suppress the static generic check when using `RootObj` workaround
- `consumeOnTransition` flag (default: `true`)
  - State types cannot be copied, preventing accidental reuse of stale states
  - Opt out with `consumeOnTransition = false`
- `initial:` and `terminal:` state declarations
  - Initial states can only be constructed, not transitioned to
  - Terminal states cannot transition to anything else
  - Validated at both DSL and transition pragma level
- Multiline state list syntax with optional newlines
  ```nim
  states:
    Closed
    Open
    Errored
  ```
- Parenthesized syntax for branching transitions: `A -> (B | C) as Result`

### Changed

- Minimum Nim version bumped to 2.2.0
- States must have unique base type names
  - Using same type with different static params (e.g., `GPIO[false]` vs `GPIO[true]`) now shows clear error
  - Documentation explains wrapper type pattern as workaround

### Documentation

- Added warning banner about Nim < 2.2.8 static generics bug to README, docs index, and getting started guide
- Added Flags section to DSL reference documenting `strictTransitions`, `consumeOnTransition`, and `inheritsFromRootObj`

## [0.2.0] - 2025-12-06

### Added

- Full helper code generation for generic typestates (`Container[T]`, `Map[K, V]`)
  - State enum (e.g., `ContainerState`)
  - Union type with generics (e.g., `ContainerStates[T]`)
  - Generic state procs (e.g., `proc state[T](c: Empty[T]): ContainerState`)
  - Generic branch types (e.g., `FillResult[T]`)
  - Generic branch constructors (e.g., `toFillResult[T]`)
  - Generic branch operators (e.g., `FillResult[T] -> Full[T](...)`)
- Support for constrained generic parameters (`N: static int`, `T: SomeNumber`, etc.)
- Cross-type state bridges (`bridges:` block for transitioning between typestates)
- `>>>` operator for branch type construction (deprecated in favor of `->`)
- Explicit `as TypeName` syntax required for branching transitions
- Comprehensive test suite with should-compile and should-fail test categories
- Styled DOT output with deep purple theme matching mkdocs-material
  - Rounded boxes with purple borders (#673ab7)
  - Transparent background for web embedding
  - Differentiated edge styles: solid (normal), dotted gray (wildcard), dashed purple (bridges)
- CLI visualization options
  - `--splines=MODE` for edge routing: `spline` (curved, default), `ortho` (right-angle), `polyline`, `line`
  - `--separate` to generate one graph per typestate
  - `--no-style` for minimal DOT output without styling
- Smart edge distribution using compass points for cleaner diagrams
- Dark mode styling for diagrams matching mkdocs-material slate theme
- Auto-generated diagram infrastructure
  - `examples/snippets/` directory for diagram source files
  - `scripts/generate_diagrams.py` for batch SVG generation
- CI compilation tests for all example files
- `mkdocs-include-markdown-plugin` for embedding code snippets
- Contributing guide

### Changed

- Documentation updated with accurate code samples matching actual library behavior
- Visualization guide updated with new styled DOT format and edge style reference
- Improved node spacing and margins for better readability
- Use Inter font stack for consistent typography

### Fixed

- Validate bridge destination states exist in target typestate
- Validate no duplicate branching transitions from same source state
- Generic branch type lookup now correctly matches types with constraints (e.g., `EmptyCheck[N]`)
- All example files now compile (added missing `as TypeName` on branching transitions)
- Pin `click<8.3.0` to fix mkdocs serve file watching
- Removed auto-regeneration hook that caused infinite rebuild loops

## [0.1.0] - 2025-12-03

### Added

- `typestate` macro for declaring states and transitions
- `{.transition.}` pragma with compile-time validation
- `{.notATransition.}` pragma for non-transitioning operations
- Branching transitions (`A -> B | C`)
- Wildcard transitions (`* -> A`)
- Generic typestate support (`typestate Container[T]`)
- Strict mode with `strictTransitions` flag
- Sealed typestates with `isSealed` flag
- Generated helper types (`FileState` enum, `FileStates` union)
- `{.raises: [].}` enforcement on transitions
- CLI tool (`typestates`) for verification and DOT graph generation

[Unreleased]: https://github.com/elijahr/nim-typestates/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/elijahr/nim-typestates/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/elijahr/nim-typestates/compare/v0.7.2...v0.8.0
[0.7.2]: https://github.com/elijahr/nim-typestates/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/elijahr/nim-typestates/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/elijahr/nim-typestates/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/elijahr/nim-typestates/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/elijahr/nim-typestates/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/elijahr/nim-typestates/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/elijahr/nim-typestates/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/elijahr/nim-typestates/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/elijahr/nim-typestates/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/elijahr/nim-typestates/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/elijahr/nim-typestates/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/elijahr/nim-typestates/releases/tag/v0.1.0
