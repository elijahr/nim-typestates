## Test user-defined branch types for branching transitions.

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
  consumeOnTransition = false  # Opt out for this test to allow reusing states
  states Created, Approved, Declined, Review, Processed
  transitions:
    # Branching transition: 3 possible outcomes with user-defined type name
    Created -> Approved | Declined | Review as CreatedBranch
    # Another branching transition: 2 outcomes
    Review -> Approved | Declined as ReviewBranch
    # Simple transitions (no branch type generated)
    Approved -> Processed
    Declined -> Processed

suite "Branch Types":
  test "CreatedBranch type exists and has correct structure":
    # The enum should exist with c prefix (first letter of CreatedBranch)
    check cApproved is CreatedBranchKind
    check cDeclined is CreatedBranchKind
    check cReview is CreatedBranchKind

    # The variant should exist and be constructible
    let b1 = CreatedBranch(kind: cApproved, approved: Approved(Payment(amount: 100)))
    check b1.kind == cApproved
    check b1.approved.Payment.amount == 100

  test "ReviewBranch type exists":
    # The enum should exist with r prefix (first letter of ReviewBranch)
    check rApproved is ReviewBranchKind
    check rDeclined is ReviewBranchKind

    let b = ReviewBranch(kind: rDeclined, declined: Declined(Payment(amount: 50)))
    check b.kind == rDeclined

  test "toCreatedBranch constructors work":
    let approved = Approved(Payment(amount: 100))
    let declined = Declined(Payment(amount: 25))
    let review = Review(Payment(amount: 75))

    let b1 = toCreatedBranch(approved)
    check b1.kind == cApproved
    check b1.approved.Payment.amount == 100

    let b2 = toCreatedBranch(declined)
    check b2.kind == cDeclined
    check b2.declined.Payment.amount == 25

    let b3 = toCreatedBranch(review)
    check b3.kind == cReview
    check b3.review.Payment.amount == 75

  test "toReviewBranch constructors work":
    let approved = Approved(Payment(amount: 100))
    let declined = Declined(Payment(amount: 25))

    let b1 = toReviewBranch(approved)
    check b1.kind == rApproved

    let b2 = toReviewBranch(declined)
    check b2.kind == rDeclined

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

    check process(high).kind == cApproved
    check process(mid).kind == cReview
    check process(low).kind == cDeclined

  test "pattern matching on branch result":
    proc process(c: Created): CreatedBranch {.transition.} =
      if c.Payment.amount > 50:
        toCreatedBranch(Approved(c.Payment))
      else:
        toCreatedBranch(Declined(c.Payment))

    let result = process(Created(Payment(amount: 100)))

    case result.kind
    of cApproved:
      check result.approved.Payment.amount == 100
    of cDeclined:
      fail()
    of cReview:
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

    check firstResult.kind == cReview

    let secondResult = reviewDecision(firstResult.review, approve = true)
    check secondResult.kind == rApproved

  test "-> operator works":
    let approved = Approved(Payment(amount: 100))
    let declined = Declined(Payment(amount: 25))

    # CreatedBranch -> State is sugar for toCreatedBranch(State)
    let b1 = CreatedBranch -> approved
    check b1.kind == cApproved
    check b1.approved.Payment.amount == 100

    let b2 = CreatedBranch -> declined
    check b2.kind == cDeclined

  test "-> operator in transition proc":
    proc processWithOperator(c: Created): CreatedBranch {.transition.} =
      if c.Payment.amount > 100:
        CreatedBranch -> Approved(c.Payment)
      elif c.Payment.amount > 50:
        CreatedBranch -> Review(c.Payment)
      else:
        CreatedBranch -> Declined(c.Payment)

    check processWithOperator(Created(Payment(amount: 150))).kind == cApproved
    check processWithOperator(Created(Payment(amount: 75))).kind == cReview
    check processWithOperator(Created(Payment(amount: 25))).kind == cDeclined

  test "-> operator disambiguates between branch types":
    # Same destination state (Approved) in different branch types
    let approved = Approved(Payment(amount: 100))

    # Explicitly choose which branch type
    let fromCreated = CreatedBranch -> approved
    let fromReview = ReviewBranch -> approved

    check fromCreated.kind == cApproved
    check fromReview.kind == rApproved

    # They're different types
    check fromCreated is CreatedBranch
    check fromReview is ReviewBranch
