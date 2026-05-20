# AGENTS.md — typestates

Guidance for AI assistants (and humans) contributing to nim-typestates.

## Pattern Signals from v0.9.0

### Pattern signal: the Green Mirage (over-conservative skip predicates)

When a verifier (or analyzer, or any default-deny / default-allow
classifier) emits a false-fire on a canonical shape, the tempting fix
is to add a skip predicate that exempts the shape's *category*:

```nim
for tp in params:
  if tp.isSink: continue   # avoid the false-fire on `result = Dst(s.Base)`
  analyze(tp)
```

This is the **Green Mirage**: tests go green, fixtures go green,
examples run clean — but the skip silently exempts an entire category
from analysis. Any real soundness gap in the exempted category now
passes review.

Observed in typestates v0.9.0 r9 → r14: an `if isSink: continue`
introduced to suppress a single false-fire on canonical sink-consume
shapes survived 4 review rounds while masking the gap on every
sink-T transition proc that failed to consume. The fix was to revert
the skip and improve the under-recognition that caused the original
false-fire (dot-call recognition in `extractTrackedLocal`).

#### Rule

When introducing a default-deny / skip / continue predicate to a
verifier or analyzer:

1. **Identify the under-recognition.** What shape did the verifier
   fail to model that caused the false-fire?
2. **Estimate the blast radius.** What real errors in the same
   category does the predicate now exempt? Write at least one
   negative fixture that the skip would silently pass.
3. **Prefer improving recognition over skipping.** If the under-
   recognition can be fixed at the call-shape / AST / type-info
   layer, do that. The skip is the last resort, not the first.
4. **If you must skip, document the exemption.** A comment naming
   the exempted shape and the planned recognition improvement is
   load-bearing — it makes the skip removable when the recognition
   lands.
