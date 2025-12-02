# Examples

Real-world patterns where typestates prevent expensive bugs.

!!! tip "Running the Examples"
    All examples in this guide are available as complete, runnable files in the [`examples/`](https://github.com/elijahr/nim-typestates/tree/main/examples) directory.

## Payment Processing

Payment processing requires strict ordering: authorize before capture, capture before refund. Typestates prevent costly mistakes like double-capture or refunds before capture.

```nim
import typestates

type
  Payment = object
    id: string
    amount: int           # cents, to avoid float issues
    authCode: string
    refundedAmount: int

  Created = distinct Payment
  Authorized = distinct Payment
  Captured = distinct Payment
  PartiallyRefunded = distinct Payment
  FullyRefunded = distinct Payment
  Settled = distinct Payment

typestate Payment:
  states Created, Authorized, Captured, PartiallyRefunded, FullyRefunded, Settled
  transitions:
    Created -> Authorized
    Authorized -> Captured
    Captured -> PartiallyRefunded | FullyRefunded | Settled
    PartiallyRefunded -> PartiallyRefunded | FullyRefunded | Settled
    FullyRefunded -> Settled

proc authorize(p: Created, cardToken: string): Authorized {.transition.} =
  var payment = p.Payment
  payment.authCode = "AUTH_" & payment.id
  echo "Authorized $", payment.amount
  result = Authorized(payment)

proc capture(p: Authorized): Captured {.transition.} =
  echo "Captured $", p.Payment.amount
  result = Captured(p.Payment)

proc partialRefund(p: Captured, amount: int): PartiallyRefunded {.transition.} =
  var payment = p.Payment
  payment.refundedAmount = amount
  echo "Refunded $", amount
  result = PartiallyRefunded(payment)

proc settle(p: Captured): Settled {.transition.} =
  echo "Settled $", p.Payment.amount
  result = Settled(p.Payment)

# Usage
var payment = Created(Payment(id: "pay_123", amount: 9999))
let authed = payment.authorize("card_tok_visa")
let captured = authed.capture()
let settled = captured.settle()

# COMPILE ERRORS - The bugs we prevent:
# payment.capture()        # Can't capture without auth
# captured.capture()       # Can't capture twice
# authed.partialRefund(50) # Can't refund before capture
```

**Bugs prevented:**

- Capturing before authorization
- Double-capture
- Refunding before capture
- Operations on settled payments

---

## Database Connection Pool

Connection pools have invariants that are easy to violate: don't query pooled connections, don't return connections mid-transaction, don't commit without a transaction.

```nim
import typestates

type
  DbConnection = object
    id: int
    inTransaction: bool

  Pooled = distinct DbConnection
  CheckedOut = distinct DbConnection
  InTransaction = distinct DbConnection
  Closed = distinct DbConnection

typestate DbConnection:
  states Pooled, CheckedOut, InTransaction, Closed
  transitions:
    Pooled -> CheckedOut | Closed
    CheckedOut -> Pooled | InTransaction | Closed
    InTransaction -> CheckedOut
    * -> Closed

proc checkout(conn: Pooled): CheckedOut {.transition.} =
  echo "Checked out connection #", conn.DbConnection.id
  result = CheckedOut(conn.DbConnection)

proc release(conn: CheckedOut): Pooled {.transition.} =
  echo "Released connection #", conn.DbConnection.id
  result = Pooled(conn.DbConnection)

proc beginTransaction(conn: CheckedOut): InTransaction {.transition.} =
  echo "BEGIN TRANSACTION"
  result = InTransaction(conn.DbConnection)

proc commit(conn: InTransaction): CheckedOut {.transition.} =
  echo "COMMIT"
  result = CheckedOut(conn.DbConnection)

proc execute(conn: CheckedOut, sql: string): CheckedOut {.notATransition.} =
  echo "Execute: ", sql
  result = conn

proc execute(conn: InTransaction, sql: string): InTransaction {.notATransition.} =
  echo "Execute (in tx): ", sql
  result = conn

# Usage
var pooledConn = Pooled(DbConnection(id: 42))
let conn = pooledConn.checkout()
let tx = conn.beginTransaction()
let tx2 = tx.execute("INSERT INTO users VALUES (1, 'alice')")
let afterTx = tx2.commit()
let returned = afterTx.release()

# COMPILE ERRORS:
# returned.execute("SELECT 1")  # Can't query pooled connection
# tx.release()                  # Can't release during transaction
# conn.commit()                 # Can't commit without transaction
```

**Bugs prevented:**

- Query on pooled (not checked out) connection
- Returning connection while in transaction
- Committing without starting transaction
- Nested transactions

---

## HTTP Request Lifecycle

HTTP requests follow a strict sequence: set headers, send headers, send body, await response. Typestates enforce this ordering at compile time.

```nim
import typestates

type
  HttpRequest = object
    path: string
    headers: seq[(string, string)]
    body: string
    responseCode: int

  Building = distinct HttpRequest
  HeadersSent = distinct HttpRequest
  RequestSent = distinct HttpRequest
  ResponseReceived = distinct HttpRequest

typestate HttpRequest:
  states Building, HeadersSent, RequestSent, ResponseReceived
  transitions:
    Building -> HeadersSent
    HeadersSent -> RequestSent
    RequestSent -> ResponseReceived
    ResponseReceived -> Building  # Keep-alive

proc header(req: Building, key, value: string): Building {.notATransition.} =
  var r = req.HttpRequest
  r.headers.add((key, value))
  result = Building(r)

proc sendHeaders(req: Building): HeadersSent {.transition.} =
  echo ">>> Sending headers"
  result = HeadersSent(req.HttpRequest)

proc sendBody(req: HeadersSent, body: string): RequestSent {.transition.} =
  echo ">>> Sending body (", body.len, " bytes)"
  result = RequestSent(req.HttpRequest)

proc finish(req: HeadersSent): RequestSent {.transition.} =
  echo ">>> Request complete (no body)"
  result = RequestSent(req.HttpRequest)

proc awaitResponse(req: RequestSent): ResponseReceived {.transition.} =
  var r = req.HttpRequest
  r.responseCode = 200
  echo "<<< Response: ", r.responseCode
  result = ResponseReceived(r)

func statusCode(resp: ResponseReceived): int =
  resp.HttpRequest.responseCode

# Usage
let req = Building(HttpRequest(path: "/api/users"))
  .header("Accept", "application/json")
  .header("Authorization", "Bearer token")
  .sendHeaders()
  .finish()
  .awaitResponse()

echo "Status: ", req.statusCode()

# COMPILE ERRORS:
# headersSent.header("X-Late", "header")  # Can't add headers after sent
# building.sendBody("data")               # Can't send body before headers
# headersSent.statusCode()                # Can't read response yet
```

**Bugs prevented:**

- Adding headers after they're sent
- Sending body before headers
- Reading response before request complete

---

## OAuth Authentication

OAuth requires authenticated tokens for API calls and refresh tokens to renew expired access. Typestates prevent calls with missing or expired credentials.

```nim
import typestates

type
  OAuthSession = object
    accessToken: string
    refreshToken: string
    expiresAt: int64

  Unauthenticated = distinct OAuthSession
  AwaitingCallback = distinct OAuthSession
  Authenticated = distinct OAuthSession
  TokenExpired = distinct OAuthSession

typestate OAuthSession:
  states Unauthenticated, AwaitingCallback, Authenticated, TokenExpired
  transitions:
    Unauthenticated -> AwaitingCallback
    AwaitingCallback -> Authenticated
    Authenticated -> TokenExpired
    TokenExpired -> Authenticated
    * -> Unauthenticated

proc startAuth(session: Unauthenticated): AwaitingCallback {.transition.} =
  echo "Redirect to: https://auth.example.com/authorize?..."
  result = AwaitingCallback(session.OAuthSession)

proc handleCallback(session: AwaitingCallback, code: string): Authenticated {.transition.} =
  var s = session.OAuthSession
  s.accessToken = "eyJhbGc..." & code
  s.refreshToken = "refresh_" & code
  echo "Tokens received"
  result = Authenticated(s)

proc callApi(session: Authenticated, endpoint: string): string {.notATransition.} =
  echo "GET ", endpoint, " (Bearer ", session.OAuthSession.accessToken[0..10], "...)"
  result = """{"status": "ok"}"""

proc tokenExpired(session: Authenticated): TokenExpired {.transition.} =
  echo "Token expired!"
  result = TokenExpired(session.OAuthSession)

proc refresh(session: TokenExpired): Authenticated {.transition.} =
  echo "Refreshing token..."
  result = Authenticated(session.OAuthSession)

# Usage
let session = Unauthenticated(OAuthSession())
  .startAuth()
  .handleCallback("auth_code_xyz")

let data = session.callApi("/api/user/me")
let expired = session.tokenExpired()
let refreshed = expired.refresh()

# COMPILE ERRORS:
# Unauthenticated(OAuthSession()).callApi("/api")  # Can't call API unauthenticated
# expired.callApi("/api")                          # Can't call API with expired token
# session.refresh()                                # Can't refresh non-expired token
```

**Bugs prevented:**

- API calls without authentication
- API calls with expired token
- Refreshing non-expired token
- Handling callback twice

---

## Robot Arm Controller

Hardware control requires strict operation sequences. Moving without homing can crash into limits; powering off during movement can damage motors.

```nim
import typestates

type
  RobotArm = object
    x, y, z: float

  PoweredOff = distinct RobotArm
  NeedsHoming = distinct RobotArm
  Homing = distinct RobotArm
  Ready = distinct RobotArm
  Moving = distinct RobotArm
  EmergencyStop = distinct RobotArm

typestate RobotArm:
  states PoweredOff, NeedsHoming, Homing, Ready, Moving, EmergencyStop
  transitions:
    PoweredOff -> NeedsHoming
    NeedsHoming -> Homing
    Homing -> Ready
    Ready -> Moving | PoweredOff
    Moving -> Ready | EmergencyStop
    EmergencyStop -> NeedsHoming | PoweredOff

proc powerOn(arm: PoweredOff): NeedsHoming {.transition.} =
  echo "Powering on... Position unknown!"
  result = NeedsHoming(arm.RobotArm)

proc startHoming(arm: NeedsHoming): Homing {.transition.} =
  echo "Finding home position..."
  result = Homing(arm.RobotArm)

proc homingComplete(arm: Homing): Ready {.transition.} =
  echo "Homing complete. Ready!"
  result = Ready(arm.RobotArm)

proc moveTo(arm: Ready, x, y, z: float): Moving {.transition.} =
  echo "Moving to (", x, ", ", y, ", ", z, ")..."
  result = Moving(arm.RobotArm)

proc moveComplete(arm: Moving): Ready {.transition.} =
  echo "Move complete"
  result = Ready(arm.RobotArm)

proc emergencyStop(arm: Moving, reason: string): EmergencyStop {.transition.} =
  echo "!!! EMERGENCY STOP: ", reason
  result = EmergencyStop(arm.RobotArm)

proc powerOff(arm: Ready): PoweredOff {.transition.} =
  echo "Powering off safely"
  result = PoweredOff(arm.RobotArm)

# Usage
var arm = PoweredOff(RobotArm())
let ready = arm.powerOn().startHoming().homingComplete()
let moving = ready.moveTo(100.0, 50.0, 20.0)
let done = moving.moveComplete()
let off = done.powerOff()

# COMPILE ERRORS - These could damage equipment!
# arm.moveTo(100, 0, 0)     # Can't move without homing!
# moving.powerOff()         # Can't power off while moving!
# ready.startHoming()       # Already homed!
```

**Bugs prevented:**

- Moving without homing (could crash into limits)
- Power off while moving (motor damage)
- Continuing after emergency stop
- Skip initialization

---

## Order Fulfillment

Order fulfillment has a fixed sequence: place, pay, ship, deliver. Typestates ensure orders can't be shipped before payment or shipped twice.

```nim
import typestates

type
  Order = object
    id: string
    items: seq[string]
    paymentId: string
    trackingNumber: string

  Cart = distinct Order
  Placed = distinct Order
  Paid = distinct Order
  Shipped = distinct Order
  Delivered = distinct Order

typestate Order:
  states Cart, Placed, Paid, Shipped, Delivered
  transitions:
    Cart -> Placed
    Placed -> Paid
    Paid -> Shipped
    Shipped -> Delivered

proc addItem(order: Cart, item: string): Cart {.notATransition.} =
  var o = order.Order
  o.items.add(item)
  result = Cart(o)

proc placeOrder(order: Cart): Placed {.transition.} =
  echo "Order placed"
  result = Placed(order.Order)

proc pay(order: Placed, paymentId: string): Paid {.transition.} =
  var o = order.Order
  o.paymentId = paymentId
  echo "Payment received: ", paymentId
  result = Paid(o)

proc ship(order: Paid, tracking: string): Shipped {.transition.} =
  var o = order.Order
  o.trackingNumber = tracking
  echo "Shipped! Tracking: ", tracking
  result = Shipped(o)

proc confirmDelivery(order: Shipped): Delivered {.transition.} =
  echo "Delivered!"
  result = Delivered(order.Order)

# Usage
let order = Cart(Order())
  .addItem("Laptop")
  .addItem("Mouse")
  .placeOrder()
  .pay("pay_ch_123")
  .ship("1Z999AA10123456784")
  .confirmDelivery()

# COMPILE ERRORS:
# Cart(Order()).ship("TRACK")  # Can't ship cart!
# placed.ship("TRACK")         # Can't ship without payment!
# shipped.ship("TRACK2")       # Can't ship twice!
```

**Bugs prevented:**

- Ship before payment
- Double-ship
- Operations on unplaced cart

---

## Document Workflow

Document publishing enforces a review process: draft, review, approve, publish. Typestates prevent publishing without approval or editing published content.

```nim
import typestates

type
  Document = object
    title: string
    content: string
    approver: string

  Draft = distinct Document
  InReview = distinct Document
  Approved = distinct Document
  Published = distinct Document

typestate Document:
  states Draft, InReview, Approved, Published
  transitions:
    Draft -> InReview
    InReview -> Approved | Draft  # Approve or request changes
    Approved -> Published
    Published -> Draft  # New version

proc edit(doc: Draft, content: string): Draft {.notATransition.} =
  var d = doc.Document
  d.content = content
  result = Draft(d)

proc submitForReview(doc: Draft): InReview {.transition.} =
  echo "Submitted for review"
  result = InReview(doc.Document)

proc approve(doc: InReview, approver: string): Approved {.transition.} =
  var d = doc.Document
  d.approver = approver
  echo "Approved by: ", approver
  result = Approved(d)

proc requestChanges(doc: InReview): Draft {.transition.} =
  echo "Changes requested"
  result = Draft(doc.Document)

proc publish(doc: Approved): Published {.transition.} =
  echo "Published!"
  result = Published(doc.Document)

# Usage
let doc = Draft(Document(title: "Q4 Strategy"))
  .edit("Our goals for Q4...")
  .submitForReview()
  .approve("carol@company.com")
  .publish()

# COMPILE ERRORS:
# draft.publish()          # Can't publish without approval!
# inReview.publish()       # Review not complete!
# published.edit("hack")   # Can't edit published content!
```

**Bugs prevented:**

- Publishing without approval
- Editing published content
- Skipping review process

---

## Generic Patterns

The following examples show reusable typestate patterns using generics. See [Generic Typestates](generics.md) for more on generic support.

### Resource[T] Pattern

A reusable pattern for any resource requiring acquire/release semantics. Works with file handles, locks, connections, memory allocations, or any RAII-style resource.

```nim
import typestates

type
  Resource[T] = object
    handle: T
    name: string

  Released[T] = distinct Resource[T]
  Acquired[T] = distinct Resource[T]

typestate Resource[T]:
  states Released[T], Acquired[T]
  transitions:
    Released[T] -> Acquired[T]
    Acquired[T] -> Released[T]

proc acquire[T](r: Released[T], handle: T): Acquired[T] {.transition.} =
  var res = Resource[T](r)
  res.handle = handle
  result = Acquired[T](res)

proc release[T](r: Acquired[T]): Released[T] {.transition.} =
  result = Released[T](Resource[T](r))

proc use[T](r: Acquired[T]): T {.notATransition.} =
  Resource[T](r).handle
```

Use with any resource type:

```nim
# File handles
type FileHandle = object
  fd: int
  path: string

var file = Released[FileHandle](Resource[FileHandle](name: "config"))
let acquired = file.acquire(FileHandle(fd: 42, path: "/etc/config"))
echo acquired.use().path  # OK
let released = acquired.release()
# released.use()  # COMPILE ERROR: can't use released resource

# Database connections
type DbConn = object
  connString: string

var db = Released[DbConn](Resource[DbConn](name: "postgres"))
let conn = db.acquire(DbConn(connString: "postgresql://localhost/mydb"))
# ...use connection...
discard conn.release()

# Locks
type Lock = object
  id: int

var mutex = Released[Lock](Resource[Lock](name: "mutex"))
let locked = mutex.acquire(Lock(id: 1))
# ...critical section...
discard locked.release()
```

**Pattern benefits:**

- Compile-time prevention of use-after-release
- Works with any resource type
- Enforces acquire-before-use
- Clean RAII semantics

---

### Pipeline[T] Pattern

A reusable pattern for entities that progress through a fixed sequence of stages. Works for orders, documents, builds, deployments, or any linear workflow.

```nim
import typestates

type
  Pipeline[T] = object
    entity: T

  Stage1[T] = distinct Pipeline[T]
  Stage2[T] = distinct Pipeline[T]
  Stage3[T] = distinct Pipeline[T]
  Stage4[T] = distinct Pipeline[T]

typestate Pipeline[T]:
  states Stage1[T], Stage2[T], Stage3[T], Stage4[T]
  transitions:
    Stage1[T] -> Stage2[T]
    Stage2[T] -> Stage3[T]
    Stage3[T] -> Stage4[T]

proc start[T](entity: T): Stage1[T] =
  Stage1[T](Pipeline[T](entity: entity))

proc advance12[T](p: Stage1[T]): Stage2[T] {.transition.} =
  Stage2[T](Pipeline[T](p))

proc advance23[T](p: Stage2[T]): Stage3[T] {.transition.} =
  Stage3[T](Pipeline[T](p))

proc advance34[T](p: Stage3[T]): Stage4[T] {.transition.} =
  Stage4[T](Pipeline[T](p))

proc entity[T](p: Stage1[T]): T {.notATransition.} = Pipeline[T](p).entity
proc entity[T](p: Stage2[T]): T {.notATransition.} = Pipeline[T](p).entity
proc entity[T](p: Stage3[T]): T {.notATransition.} = Pipeline[T](p).entity
proc entity[T](p: Stage4[T]): T {.notATransition.} = Pipeline[T](p).entity
```

Apply to different domains with semantic aliases:

```nim
# Order fulfillment
type Order = object
  id: string
  items: seq[string]

type
  OrderCart = Stage1[Order]      # Cart
  OrderPaid = Stage2[Order]      # Paid
  OrderShipped = Stage3[Order]   # Shipped
  OrderDelivered = Stage4[Order] # Delivered

let order = start(Order(id: "ORD-001"))
let paid = order.advance12()      # Cart -> Paid
let shipped = paid.advance23()    # Paid -> Shipped
let delivered = shipped.advance34() # Shipped -> Delivered

# order.advance23()  # COMPILE ERROR: can't skip Paid stage

# CI/CD builds
type Build = object
  repo: string
  commit: string

type
  BuildQueued = Stage1[Build]
  BuildCompiling = Stage2[Build]
  BuildTesting = Stage3[Build]
  BuildDeployed = Stage4[Build]

# Document review
type Document = object
  title: string
  content: string

type
  DocDraft = Stage1[Document]
  DocInReview = Stage2[Document]
  DocApproved = Stage3[Document]
  DocPublished = Stage4[Document]
```

**Pattern benefits:**

- Enforces stage ordering at compile time
- Prevents skipping stages
- Single definition works for any entity type
- Domain-specific naming via type aliases

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
