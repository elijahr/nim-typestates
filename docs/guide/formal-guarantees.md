# Formal Guarantees

This page explains the verification properties that nim-typestates provides
and how they relate to formal methods concepts.

## Correctness by Construction

nim-typestates implements a form of correctness by construction: rather than
testing for state machine violations at runtime, the type system makes them
impossible to express.

The Nim compiler acts as a verifier. If compilation succeeds, the program
has been proven to contain no invalid state transitions.

## What is Verified

### Temporal Safety

Standard type systems verify *data safety*: a variable declared as `int`
cannot be used as a `string`. Typestates extend this to *temporal safety*:
an object in state `Closed` cannot be used where state `Open` is required.

This prevents a class of bugs where operations are called in the wrong order
or on objects in invalid states.

### Protocol Adherence

Each `{.transition.}` proc is checked against the declared state graph.
The compiler rejects any proc that:

- Takes a state type not registered in a typestate
- Returns a state not reachable from the input state
- Implements an undeclared transition

### State Exclusivity

Distinct types ensure an object cannot satisfy multiple state types
simultaneously. The type `Closed` is incompatible with `Open` at the
type level, not just the value level.

## Limitations

### Specification Correctness

The compiler verifies that code follows the declared state machine. It does
not verify that the state machine correctly models the intended protocol.

If the specification is wrong, the implementation will be "correctly wrong."

### Functional Correctness

Typestates verify *when* operations can be called, not *what* they do.
A `{.transition.}` proc from `Closed` to `Open` is verified to be callable
only on `Closed` values and to return `Open` values. The proc body itself
is not verified.

### Runtime Behavior

Typestates operate at compile time. Runtime properties such as performance,
memory safety, or exception behavior are outside their scope.

## Comparison to Full Formal Verification

| Aspect | nim-typestates | Full Formal Methods (TLA+, Coq) |
|--------|----------------|----------------------------------|
| What is verified | Protocol adherence | Functional correctness |
| Verification method | Type checking | Theorem proving |
| Effort required | Automatic | Manual proofs |
| Typical use | Application protocols | Safety-critical systems |

nim-typestates occupies a practical middle ground: stronger guarantees than
testing, lower cost than full formal verification.

## Further Reading

- [Typestate Analysis (Wikipedia)](https://en.wikipedia.org/wiki/Typestate_analysis)
- [Formal Verification (Wikipedia)](https://en.wikipedia.org/wiki/Formal_verification)
- [Typestates for Objects (Aldrich et al., 2009)](https://www.cs.cmu.edu/~aldrich/papers/classic/tse12-typestate.pdf)
- [Typestate: A Programming Language Concept (Strom & Yemini, 1986)](https://doi.org/10.1109/TSE.1986.6312929)
- [The Typestate Pattern in Rust](https://cliffle.com/blog/rust-typestate/)
- [Plaid Programming Language](http://www.cs.cmu.edu/~aldrich/plaid/)
