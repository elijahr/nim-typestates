## Generic Pipeline[T] Pattern
##
## A reusable typestate pattern for entities that progress through
## a fixed sequence of stages. Works for orders, documents, builds,
## deployments, or any linear workflow.
##
## Run: nim c -r examples/generic_pipeline.nim

import ../src/typestates

# =============================================================================
# Generic Pipeline Pattern (4-stage)
# =============================================================================

type
  Pipeline*[T] = object
    ## Base type holding the entity progressing through stages.
    entity*: T
    startedAt*: string

  Stage1*[T] = distinct Pipeline[T]
    ## Initial stage - entity just entered the pipeline.

  Stage2*[T] = distinct Pipeline[T]
    ## Second stage - first transition complete.

  Stage3*[T] = distinct Pipeline[T]
    ## Third stage - nearing completion.

  Stage4*[T] = distinct Pipeline[T]
    ## Final stage - pipeline complete.

typestate Pipeline[T]:
  states Stage1[T], Stage2[T], Stage3[T], Stage4[T]
  transitions:
    Stage1[T] -> Stage2[T]
    Stage2[T] -> Stage3[T]
    Stage3[T] -> Stage4[T]

proc start*[T](entity: T, timestamp: string): Stage1[T] =
  ## Enter the pipeline at stage 1.
  Stage1[T](Pipeline[T](entity: entity, startedAt: timestamp))

proc advance12*[T](p: Stage1[T]): Stage2[T] {.transition.} =
  ## Advance from stage 1 to stage 2.
  Stage2[T](Pipeline[T](p))

proc advance23*[T](p: Stage2[T]): Stage3[T] {.transition.} =
  ## Advance from stage 2 to stage 3.
  Stage3[T](Pipeline[T](p))

proc advance34*[T](p: Stage3[T]): Stage4[T] {.transition.} =
  ## Advance from stage 3 to stage 4 (complete).
  Stage4[T](Pipeline[T](p))

proc entity*[T](p: Stage1[T]): T {.notATransition.} = Pipeline[T](p).entity
proc entity*[T](p: Stage2[T]): T {.notATransition.} = Pipeline[T](p).entity
proc entity*[T](p: Stage3[T]): T {.notATransition.} = Pipeline[T](p).entity
proc entity*[T](p: Stage4[T]): T {.notATransition.} = Pipeline[T](p).entity

# =============================================================================
# Example 1: Order Fulfillment
# =============================================================================

type
  Order = object
    id: string
    items: seq[string]
    total: int

  # Semantic aliases for order stages
  OrderCart = Stage1[Order]
  OrderPaid = Stage2[Order]
  OrderShipped = Stage3[Order]
  OrderDelivered = Stage4[Order]

proc addItem(cart: OrderCart, item: string, price: int): OrderCart {.notATransition.} =
  var order = cart.entity()
  order.items.add(item)
  order.total += price
  Stage1[Order](Pipeline[Order](entity: order, startedAt: Pipeline[Order](cart).startedAt))

proc pay(cart: OrderCart): OrderPaid =
  echo "  Payment received: $", cart.entity().total
  cart.advance12()

proc ship(order: OrderPaid, tracking: string): OrderShipped =
  echo "  Shipped with tracking: ", tracking
  order.advance23()

proc deliver(order: OrderShipped): OrderDelivered =
  echo "  Delivered!"
  order.advance34()

block orderExample:
  echo "\n=== Order Fulfillment Example ==="

  let cart = start(Order(id: "ORD-001"), "2024-01-15")
    .addItem("Laptop", 999)
    .addItem("Mouse", 29)
    .addItem("Keyboard", 79)

  echo "  Cart total: $", cart.entity().total

  let paid = cart.pay()
  let shipped = paid.ship("1Z999AA10123456784")
  let delivered = shipped.deliver()

  echo "  Order ", delivered.entity().id, " complete!"

  # COMPILE ERRORS if uncommented:
  # discard cart.ship("TRACK")      # Can't ship unpaid cart
  # discard shipped.pay()           # Can't pay already-shipped order
  # discard delivered.advance34()   # Can't advance past final stage

# =============================================================================
# Example 2: CI/CD Build Pipeline
# =============================================================================

type
  Build = object
    repo: string
    commit: string
    artifacts: seq[string]

  # Semantic aliases for build stages
  BuildQueued = Stage1[Build]
  BuildCompiling = Stage2[Build]
  BuildTesting = Stage3[Build]
  BuildDeployed = Stage4[Build]

proc startBuild(repo, commit: string): BuildQueued =
  echo "  Build queued for ", repo, "@", commit[0..6]
  start(Build(repo: repo, commit: commit), "now")

proc compile(build: BuildQueued): BuildCompiling =
  echo "  Compiling..."
  var b = build.entity()
  b.artifacts.add("app.bin")
  let pipeline = Pipeline[Build](entity: b, startedAt: Pipeline[Build](build).startedAt)
  Stage2[Build](pipeline)

proc test(build: BuildCompiling): BuildTesting =
  echo "  Running tests..."
  build.advance23()

proc deploy(build: BuildTesting): BuildDeployed =
  echo "  Deploying artifacts: ", build.entity().artifacts
  build.advance34()

block buildExample:
  echo "\n=== CI/CD Build Pipeline Example ==="

  let deployed = startBuild("github.com/user/project", "abc123def456")
    .compile()
    .test()
    .deploy()

  echo "  Build complete for ", deployed.entity().repo

  # COMPILE ERRORS:
  # discard startBuild("repo", "commit").deploy()  # Can't skip stages!

# =============================================================================
# Example 3: Document Review
# =============================================================================

type
  Document = object
    title: string
    content: string
    reviewer: string
    approver: string

  # Semantic aliases
  DocDraft = Stage1[Document]
  DocInReview = Stage2[Document]
  DocApproved = Stage3[Document]
  DocPublished = Stage4[Document]

proc createDraft(title: string): DocDraft =
  start(Document(title: title), "draft-created")

proc edit(doc: DocDraft, content: string): DocDraft {.notATransition.} =
  var d = doc.entity()
  d.content = content
  Stage1[Document](Pipeline[Document](entity: d, startedAt: Pipeline[Document](doc).startedAt))

proc submitForReview(doc: DocDraft, reviewer: string): DocInReview =
  var d = doc.entity()
  d.reviewer = reviewer
  echo "  Submitted to ", reviewer, " for review"
  let pipeline = Pipeline[Document](entity: d, startedAt: Pipeline[Document](doc).startedAt)
  Stage2[Document](pipeline)

proc approve(doc: DocInReview, approver: string): DocApproved =
  var d = doc.entity()
  d.approver = approver
  echo "  Approved by ", approver
  let pipeline = Pipeline[Document](entity: d, startedAt: Pipeline[Document](doc).startedAt)
  Stage3[Document](pipeline)

proc publish(doc: DocApproved): DocPublished =
  echo "  Published: ", doc.entity().title
  doc.advance34()

block docExample:
  echo "\n=== Document Review Example ==="

  let published = createDraft("Q4 Strategy")
    .edit("Our goals for Q4 include...")
    .submitForReview("alice@company.com")
    .approve("bob@company.com")
    .publish()

  echo "  Document '", published.entity().title, "' is live!"

  # COMPILE ERRORS:
  # discard createDraft("Doc").publish()  # Can't publish without review!

# =============================================================================
# Example 4: Deployment Pipeline
# =============================================================================

type
  Deployment = object
    service: string
    version: string
    environment: string

  # Semantic aliases
  DeployStaging = Stage1[Deployment]
  DeployCanary = Stage2[Deployment]
  DeployPartial = Stage3[Deployment]
  DeployFull = Stage4[Deployment]

proc deployToStaging(service, version: string): DeployStaging =
  echo "  Deploying ", service, " v", version, " to staging"
  start(Deployment(service: service, version: version, environment: "staging"), "now")

proc promoteToCanary(d: DeployStaging): DeployCanary =
  echo "  Promoting to canary (1% traffic)"
  var dep = d.entity()
  dep.environment = "canary"
  Stage2[Deployment](Pipeline[Deployment](entity: dep, startedAt: "now"))

proc expandToPartial(d: DeployCanary): DeployPartial =
  echo "  Expanding to 25% traffic"
  var dep = d.entity()
  dep.environment = "partial"
  Stage3[Deployment](Pipeline[Deployment](entity: dep, startedAt: "now"))

proc rolloutFull(d: DeployPartial): DeployFull =
  echo "  Full rollout to 100% traffic"
  var dep = d.entity()
  dep.environment = "production"
  Stage4[Deployment](Pipeline[Deployment](entity: dep, startedAt: "now"))

block deployExample:
  echo "\n=== Deployment Pipeline Example ==="

  let production = deployToStaging("api-server", "2.3.0")
    .promoteToCanary()
    .expandToPartial()
    .rolloutFull()

  echo "  ", production.entity().service, " v", production.entity().version,
       " is now in ", production.entity().environment

# =============================================================================
# Summary
# =============================================================================

echo "\n=== Summary ==="
echo "The Pipeline[T] pattern ensures:"
echo "  - Entities must progress through stages in order"
echo "  - No stage can be skipped"
echo "  - Operations are only valid at appropriate stages"
echo "  - Works with ANY entity type via generics"
echo ""
echo "Common applications:"
echo "  - Order fulfillment (Cart -> Paid -> Shipped -> Delivered)"
echo "  - CI/CD builds (Queue -> Compile -> Test -> Deploy)"
echo "  - Document review (Draft -> Review -> Approve -> Publish)"
echo "  - Canary deployments (Staging -> Canary -> Partial -> Full)"

echo "\nAll examples passed!"
