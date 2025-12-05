## Snippet: Database Connection typestate definition
## Used by docs for include-markdown

import ../../src/typestates

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
    Pooled -> CheckedOut | Closed as CheckoutResult
    CheckedOut -> Pooled | InTransaction | Closed as CheckoutAction
    InTransaction -> CheckedOut
    * -> Closed
