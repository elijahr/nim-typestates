# Examples

Real-world patterns where typestates prevent expensive bugs.

!!! tip "Running the Examples"
    All examples are complete, runnable files in the [`examples/`](https://github.com/elijahr/nim-typestates/tree/main/examples) directory.

    ```bash
    nim c -r examples/payment_processing.nim
    ```

---

## Payment Processing

Payment processing requires strict ordering: authorize before capture, capture before refund. Typestates prevent costly mistakes like double-capture or refunds before capture.

**Bugs prevented:** Capturing before authorization, double-capture, refunding before capture, operations on settled payments.

```nim
{% include-markdown "../../examples/payment_processing.nim" %}
```

[:material-file-code: View full source](https://github.com/elijahr/nim-typestates/blob/main/examples/payment_processing.nim)

---

## Database Connection Pool

Connection pools have invariants that are easy to violate: don't query pooled connections, don't return connections mid-transaction, don't commit without a transaction.

**Bugs prevented:** Query on pooled connection, returning connection while in transaction, committing without transaction, nested transactions.

```nim
{% include-markdown "../../examples/database_connection.nim" %}
```

[:material-file-code: View full source](https://github.com/elijahr/nim-typestates/blob/main/examples/database_connection.nim)

---

## HTTP Request Lifecycle

HTTP requests follow a strict sequence: set headers, send headers, send body, await response. Typestates enforce this ordering at compile time.

**Bugs prevented:** Adding headers after sent, sending body before headers, reading response before request complete.

```nim
{% include-markdown "../../examples/http_request.nim" %}
```

[:material-file-code: View full source](https://github.com/elijahr/nim-typestates/blob/main/examples/http_request.nim)

---

## OAuth Authentication

OAuth requires authenticated tokens for API calls and refresh tokens to renew expired access. Typestates prevent calls with missing or expired credentials.

**Bugs prevented:** API calls without authentication, API calls with expired token, refreshing non-expired token.

```nim
{% include-markdown "../../examples/oauth_auth.nim" %}
```

[:material-file-code: View full source](https://github.com/elijahr/nim-typestates/blob/main/examples/oauth_auth.nim)

---

## Robot Arm Controller

Hardware control requires strict operation sequences. Moving without homing can crash into limits; powering off during movement can damage motors.

**Bugs prevented:** Moving without homing, power off while moving, continuing after emergency stop.

```nim
{% include-markdown "../../examples/robot_arm.nim" %}
```

[:material-file-code: View full source](https://github.com/elijahr/nim-typestates/blob/main/examples/robot_arm.nim)

---

## Order Fulfillment

Order fulfillment has a fixed sequence: place, pay, ship, deliver. Typestates ensure orders can't be shipped before payment or shipped twice.

**Bugs prevented:** Ship before payment, double-ship, operations on unplaced cart.

```nim
{% include-markdown "../../examples/order_fulfillment.nim" %}
```

[:material-file-code: View full source](https://github.com/elijahr/nim-typestates/blob/main/examples/order_fulfillment.nim)

---

## Document Workflow

Document publishing enforces a review process: draft, review, approve, publish. Typestates prevent publishing without approval or editing published content.

**Bugs prevented:** Publishing without approval, editing published content, skipping review process.

```nim
{% include-markdown "../../examples/document_workflow.nim" %}
```

[:material-file-code: View full source](https://github.com/elijahr/nim-typestates/blob/main/examples/document_workflow.nim)

---

## Single-Use Token (Ownership)

Some resources should only be used once: password reset tokens, one-time payment links, event tickets. This example uses `consumeOnTransition = true` (the default) to enforce that tokens cannot be copied or reused.

**Bugs prevented:** Double consumption, copying to bypass single-use, using after consumption.

```nim
{% include-markdown "../../examples/single_use_token.nim" %}
```

[:material-file-code: View full source](https://github.com/elijahr/nim-typestates/blob/main/examples/single_use_token.nim)

---

## Shared Session (ref types)

When multiple parts of code need access to the same stateful object, use `ref` types. Common for session objects, connection pools, and shared resources in async code.

**Bugs prevented:** Operations on wrong session state, accessing expired sessions.

```nim
{% include-markdown "../../examples/shared_session.nim" %}
```

[:material-file-code: View full source](https://github.com/elijahr/nim-typestates/blob/main/examples/shared_session.nim)

---

## Hardware Register (ptr types)

When interfacing with hardware or memory-mapped I/O, typestates can enforce correct access patterns with raw pointers.

**Bugs prevented:** Reading uninitialized registers, modifying locked registers.

```nim
{% include-markdown "../../examples/hardware_register.nim" %}
```

[:material-file-code: View full source](https://github.com/elijahr/nim-typestates/blob/main/examples/hardware_register.nim)

---

## Generic Patterns

Reusable typestate patterns using generics. See [Generic Typestates](generics.md) for more details.

### Resource[T] Pattern

A reusable pattern for any resource requiring acquire/release semantics.

```nim
{% include-markdown "../../examples/generic_resource.nim" %}
```

[:material-file-code: View full source](https://github.com/elijahr/nim-typestates/blob/main/examples/generic_resource.nim)

---

### Pipeline[T] Pattern

A reusable pattern for entities that progress through a fixed sequence of stages.

```nim
{% include-markdown "../../examples/generic_pipeline.nim" %}
```

[:material-file-code: View full source](https://github.com/elijahr/nim-typestates/blob/main/examples/generic_pipeline.nim)

---

## Tips for Designing Typestates

### 1. Start with the State Diagram

Draw your states and transitions first. Each arrow becomes a transition declaration.

### 2. One Responsibility Per State

Each state should represent one clear condition. If a state has multiple meanings, split it.

### 3. Use Wildcards Sparingly

`* -> X` is powerful but can hide bugs. Use it only for truly universal operations like "reset" or "emergency stop".

### 4. Consider Error States

Many real systems need error/failure states. Plan for them upfront.

### 5. Document State Meanings

Even with types enforcing transitions, document what each state means:

```nim
type
  Pending = distinct Order
    ## Order placed but not paid

  Paid = distinct Order
    ## Payment received, awaiting fulfillment

  Shipped = distinct Order
    ## Order shipped to customer
```
