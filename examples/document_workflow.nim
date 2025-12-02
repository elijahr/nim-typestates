## Document Workflow with Typestates
##
## Content publishing workflows have strict rules:
## - Publishing drafts without review: quality issues
## - Editing published content: audit/compliance problems
## - Approving your own work: process violation
## - Skipping required reviews: legal risk
##
## This example models a multi-stage document review workflow.

import ../src/typestates
import std/hashes

type
  Document = object
    id: string
    title: string
    content: string
    author: string
    reviewers: seq[string]
    approver: string
    version: int
    publishedAt: int64

  # Document states
  Draft = distinct Document           ## Being written/edited
  InReview = distinct Document        ## Submitted for review
  ChangesRequested = distinct Document ## Reviewer requested changes
  Approved = distinct Document        ## Passed review, ready to publish
  Published = distinct Document       ## Live/public
  Archived = distinct Document        ## Removed from public, preserved

typestate Document:
  states Draft, InReview, ChangesRequested, Approved, Published, Archived
  transitions:
    Draft -> InReview                    # Submit for review
    InReview -> Approved | ChangesRequested  # Review decision
    ChangesRequested -> InReview         # Resubmit after changes
    Approved -> Published                # Go live
    Published -> Archived | Draft        # Archive or create new version
    Archived -> Draft                    # Restore for new version

# ============================================================================
# Creating and Editing
# ============================================================================

proc newDocument(title: string, author: string): Draft =
  ## Create a new document draft.
  echo "  [DOC] Created: '", title, "' by ", author
  result = Draft(Document(
    id: "doc_" & $hash(title),
    title: title,
    author: author,
    version: 1
  ))

proc edit(doc: Draft, content: string): Draft {.notATransition.} =
  ## Edit the document content.
  var d = doc.Document
  d.content = content
  echo "  [DOC] Updated content (", content.len, " chars)"
  result = Draft(d)

proc setTitle(doc: Draft, title: string): Draft {.notATransition.} =
  ## Update the document title.
  var d = doc.Document
  d.title = title
  echo "  [DOC] Title changed to: '", title, "'"
  result = Draft(d)

# ============================================================================
# Review Process
# ============================================================================

proc submitForReview(doc: Draft, reviewers: seq[string]): InReview {.transition.} =
  ## Submit document for review.
  var d = doc.Document
  d.reviewers = reviewers
  echo "  [DOC] Submitted for review"
  echo "  [DOC] Reviewers: ", reviewers
  result = InReview(d)

proc approve(doc: InReview, approver: string): Approved {.transition.} =
  ## Approve the document.
  var d = doc.Document
  d.approver = approver
  echo "  [DOC] Approved by: ", approver
  result = Approved(d)

proc requestChanges(doc: InReview, feedback: string): ChangesRequested {.transition.} =
  ## Request changes to the document.
  echo "  [DOC] Changes requested: ", feedback
  result = ChangesRequested(doc.Document)

proc updateContent(doc: ChangesRequested, newContent: string): ChangesRequested {.notATransition.} =
  ## Update content while in ChangesRequested state.
  var d = doc.Document
  d.content = newContent
  echo "  [DOC] Content updated (", newContent.len, " chars)"
  result = ChangesRequested(d)

proc resubmit(doc: ChangesRequested): InReview {.transition.} =
  ## Resubmit after making changes.
  echo "  [DOC] Resubmitted for review"
  result = InReview(doc.Document)

# ============================================================================
# Publishing
# ============================================================================

proc publish(doc: Approved): Published {.transition.} =
  ## Publish the approved document.
  var d = doc.Document
  d.publishedAt = 1234567890  # In real code: current timestamp
  echo "  [DOC] Published! '", d.title, "'"
  result = Published(d)

proc archive(doc: Published, reason: string): Archived {.transition.} =
  ## Archive a published document.
  echo "  [DOC] Archived: ", reason
  result = Archived(doc.Document)

proc createNewVersion(doc: Published): Draft {.transition.} =
  ## Create a new draft version from published.
  var d = doc.Document
  d.version += 1
  d.approver = ""
  d.publishedAt = 0
  echo "  [DOC] New version ", d.version, " created from published"
  result = Draft(d)

proc restore(doc: Archived): Draft {.transition.} =
  ## Restore archived document as new draft.
  var d = doc.Document
  d.version += 1
  echo "  [DOC] Restored as version ", d.version
  result = Draft(d)

# ============================================================================
# Status Queries
# ============================================================================

func title(doc: DocumentStates): string =
  doc.Document.title

func author(doc: DocumentStates): string =
  doc.Document.author

func version(doc: DocumentStates): int =
  doc.Document.version

func isPublished(doc: Published): bool = true

# ============================================================================
# Example Usage
# ============================================================================

when isMainModule:
  echo "=== Document Workflow Demo ===\n"

  echo "1. Creating new document..."
  let draft = newDocument("Q4 Strategy Document", "alice@company.com")
    .edit("# Q4 Strategy\n\nOur goals for Q4 are...")
    .setTitle("Q4 2024 Strategy Document")

  echo "\n2. Submitting for review..."
  let review = draft.submitForReview(@["bob@company.com", "carol@company.com"])

  echo "\n3. Reviewer requests changes..."
  let needsChanges = review.requestChanges("Please add budget section")

  echo "\n4. Author makes changes and resubmits..."
  let resubmitted = needsChanges.resubmit()

  echo "\n5. Document approved..."
  let approved = resubmitted.approve("carol@company.com")

  echo "\n6. Publishing document..."
  let published = approved.publish()

  echo "\n7. Later, creating new version for updates..."
  let v2Draft = published.createNewVersion()
  let v2 = v2Draft.edit("# Q4 2024 Strategy\n\nUpdated with Q3 results...")

  echo "\n=== Workflow complete! ===\n"

  # =========================================================================
  # COMPILE-TIME ERRORS - These process violations are prevented:
  # =========================================================================

  echo "The following process violations are caught at COMPILE TIME:\n"

  # BUG 1: Publishing without approval
  # let bad1 = draft.publish()
  echo "  [PREVENTED] publish() Draft - must be approved first!"

  # BUG 2: Publishing during review
  # let bad2 = review.publish()
  echo "  [PREVENTED] publish() InReview - review not complete!"

  # BUG 3: Editing published content
  # let bad3 = published.edit("hacked content")
  echo "  [PREVENTED] edit() Published - audit violation!"

  # BUG 4: Approving draft (skipping review)
  # let bad4 = draft.approve("alice")
  echo "  [PREVENTED] approve() Draft - must go through review!"

  # BUG 5: Double-publishing
  # let bad5 = published.publish()
  echo "  [PREVENTED] publish() Published - already live!"

  # BUG 6: Requesting changes on approved doc
  # let bad6 = approved.requestChanges("wait, one more thing")
  echo "  [PREVENTED] requestChanges() Approved - too late!"

  echo "\nUncomment any of the 'bad' lines to see the compile error!"
