## Test auto-generated branch types for branching transitions.

import std/unittest
import ../src/typestates

type
  Payment = object
    amount: int
  Created = distinct Payment
  Approved = distinct Payment
  Declined = distinct Payment
  Review = distinct Payment
  Processed = distinct Payment

typestate Payment:
  states Created, Approved, Declined, Review, Processed
  transitions:
    # Branching transition: 3 possible outcomes
    Created -> Approved | Declined | Review
    # Another branching transition: 2 outcomes
    Review -> Approved | Declined
    # Simple transitions (no branch type generated)
    Approved -> Processed
    Declined -> Processed

suite "Branch Types":
  test "CreatedBranch type exists and has correct structure":
    # The enum should exist with cb prefix (c=Created, b=branch)
    check cbApproved is CreatedBranchKind
    check cbDeclined is CreatedBranchKind
    check cbReview is CreatedBranchKind

    # The variant should exist and be constructible
    let b1 = CreatedBranch(kind: cbApproved, approved: Approved(Payment(amount: 100)))
    check b1.kind == cbApproved
    check b1.approved.Payment.amount == 100

  test "ReviewBranch type exists":
    # The enum should exist with rb prefix (r=Review, b=branch)
    check rbApproved is ReviewBranchKind
    check rbDeclined is ReviewBranchKind

    let b = ReviewBranch(kind: rbDeclined, declined: Declined(Payment(amount: 50)))
    check b.kind == rbDeclined

  test "toCreatedBranch constructors work":
    let approved = Approved(Payment(amount: 100))
    let declined = Declined(Payment(amount: 25))
    let review = Review(Payment(amount: 75))

    let b1 = toCreatedBranch(approved)
    check b1.kind == cbApproved
    check b1.approved.Payment.amount == 100

    let b2 = toCreatedBranch(declined)
    check b2.kind == cbDeclined
    check b2.declined.Payment.amount == 25

    let b3 = toCreatedBranch(review)
    check b3.kind == cbReview
    check b3.review.Payment.amount == 75

  test "toReviewBranch constructors work":
    let approved = Approved(Payment(amount: 100))
    let declined = Declined(Payment(amount: 25))

    let b1 = toReviewBranch(approved)
    check b1.kind == rbApproved

    let b2 = toReviewBranch(declined)
    check b2.kind == rbDeclined

  test "branching transition with constructors":
    proc process(c: Created): CreatedBranch {.transition.} =
      if c.Payment.amount > 100:
        toCreatedBranch(Approved(c.Payment))
      elif c.Payment.amount > 50:
        toCreatedBranch(Review(c.Payment))
      else:
        toCreatedBranch(Declined(c.Payment))

    let high = Created(Payment(amount: 150))
    let mid = Created(Payment(amount: 75))
    let low = Created(Payment(amount: 25))

    check process(high).kind == cbApproved
    check process(mid).kind == cbReview
    check process(low).kind == cbDeclined

  test "pattern matching on branch result":
    proc process(c: Created): CreatedBranch {.transition.} =
      if c.Payment.amount > 50:
        toCreatedBranch(Approved(c.Payment))
      else:
        toCreatedBranch(Declined(c.Payment))

    let result = process(Created(Payment(amount: 100)))

    case result.kind
    of cbApproved:
      check result.approved.Payment.amount == 100
    of cbDeclined:
      fail()
    of cbReview:
      fail()

  test "chained branching transitions":
    proc processCreated(c: Created): CreatedBranch {.transition.} =
      toCreatedBranch(Review(c.Payment))

    proc reviewDecision(r: Review, approve: bool): ReviewBranch {.transition.} =
      if approve:
        toReviewBranch(Approved(r.Payment))
      else:
        toReviewBranch(Declined(r.Payment))

    let c = Created(Payment(amount: 75))
    let firstResult = processCreated(c)

    check firstResult.kind == cbReview

    let secondResult = reviewDecision(firstResult.review, approve = true)
    check secondResult.kind == rbApproved
