# AGENTS.md: Operational Invariants & System Guidelines

## 1. Repository & Asset Policy
- **SENSITIVE ASSETS**: Never stage or commit custom wake-word models, audio samples, or sensitive credentials.


## 2. Reified Event-Typestate Architectural Rules
All state machines in this codebase (`satellite_fsm.nim` and `nim-typestates`) must adhere to the 5 Reified Event-Typestate rules:

1. **Zero-Variable-Branching Invariant (Event Reification)**:
   - No state transition handler may inspect the *type* of an event with an `if` or `case` statement.
   - The pairing of `(State S, Event E)` must immediately instantiate a dedicated state type $S_E$.
   - Any dynamic payload evaluation (e.g. error strings, wake-word names) occurs in an explicit, typed Evaluation State (e.g. `ReplyingBargeInAttempted`).
2. **Synchronous Run-to-Completion Transitions**:
   - State transitions must be 100% synchronous and instantaneous.
   - Asynchronous jobs (network I/O, audio streaming, LLM inference) are never awaited inside state transitions; they are kicked off detached and post completion events back to the queue.
3. **Total Event Accounting**:
   - Every state must explicitly declare what happens for every possible event in the system.
   - Unhandled events must transition through an explicit `*Ignored` state or fail compile-time validation. No silent event drops.
4. **Decoupled Transport Supervision**:
   - Transport/network health is a supervisory observer, not an enum value inside the voice lifecycle FSM.
   - Grace periods (e.g. 3-second debounce) prevent fleeting ping drops from corrupting active voice queries.
5. **Deterministic Hardware / LED Binding**:
   - The LED ring and hardware registers are pure projections of the current FSM state.
