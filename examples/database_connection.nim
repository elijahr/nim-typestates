## Database Connection Pool with Typestates
##
## Connection pool bugs are among the most painful to debug:
## - Query on a closed connection: "connection already closed"
## - Return connection to pool while query is running: data corruption
## - Use connection after returning to pool: race conditions
## - Forget to return connection: pool exhaustion
##
## This example ensures compile-time safety for connection lifecycle.

import ../src/typestates

type
  DbConnection = object
    id: int
    host: string
    port: int
    database: string
    inTransaction: bool
    queryCount: int

  # Connection states
  Pooled = distinct DbConnection       ## In the pool, available for checkout
  CheckedOut = distinct DbConnection   ## Checked out, not in transaction
  InTransaction = distinct DbConnection ## Active transaction
  Closed = distinct DbConnection        ## Permanently closed

typestate DbConnection:
  states Pooled, CheckedOut, InTransaction, Closed
  transitions:
    Pooled -> CheckedOut | Closed       # Checkout or close idle connection
    CheckedOut -> Pooled | InTransaction | Closed  # Return, begin tx, or close
    InTransaction -> CheckedOut         # Commit/rollback ends transaction
    * -> Closed                         # Can always force-close

# ============================================================================
# Connection Pool Operations
# ============================================================================

proc checkout(conn: Pooled): CheckedOut {.transition.} =
  ## Get a connection from the pool for exclusive use.
  echo "  [POOL] Checked out connection #", conn.DbConnection.id
  result = CheckedOut(conn.DbConnection)

proc release(conn: CheckedOut): Pooled {.transition.} =
  ## Return connection to the pool.
  echo "  [POOL] Released connection #", conn.DbConnection.id, " (", conn.DbConnection.queryCount, " queries)"
  var c = conn.DbConnection
  c.queryCount = 0
  result = Pooled(c)

proc close(conn: Pooled): Closed {.transition.} =
  ## Close an idle connection permanently.
  echo "  [POOL] Closed idle connection #", conn.DbConnection.id
  result = Closed(conn.DbConnection)

proc close(conn: CheckedOut): Closed {.transition.} =
  ## Close a checked-out connection (emergency/error case).
  echo "  [POOL] Force-closed connection #", conn.DbConnection.id
  result = Closed(conn.DbConnection)

# ============================================================================
# Transaction Operations
# ============================================================================

proc beginTransaction(conn: CheckedOut): InTransaction {.transition.} =
  ## Start a database transaction.
  echo "  [DB] BEGIN TRANSACTION"
  var c = conn.DbConnection
  c.inTransaction = true
  result = InTransaction(c)

proc commit(conn: InTransaction): CheckedOut {.transition.} =
  ## Commit the current transaction.
  echo "  [DB] COMMIT"
  var c = conn.DbConnection
  c.inTransaction = false
  result = CheckedOut(c)

proc rollback(conn: InTransaction): CheckedOut {.transition.} =
  ## Rollback the current transaction.
  echo "  [DB] ROLLBACK"
  var c = conn.DbConnection
  c.inTransaction = false
  result = CheckedOut(c)

# ============================================================================
# Query Operations (no state change)
# ============================================================================

proc execute(conn: CheckedOut, sql: string): CheckedOut {.notATransition.} =
  ## Execute a SQL statement (outside transaction).
  var c = conn.DbConnection
  c.queryCount += 1
  echo "  [DB] Execute: ", sql
  result = CheckedOut(c)

proc execute(conn: InTransaction, sql: string): InTransaction {.notATransition.} =
  ## Execute a SQL statement (inside transaction).
  var c = conn.DbConnection
  c.queryCount += 1
  echo "  [DB] Execute (in tx): ", sql
  result = InTransaction(c)

func isInTransaction(conn: DbConnectionStates): bool =
  ## Check if connection has active transaction.
  conn.DbConnection.inTransaction

# ============================================================================
# Example Usage
# ============================================================================

when isMainModule:
  echo "=== Database Connection Demo ===\n"

  # Simulate a connection pool
  var pooledConn = Pooled(DbConnection(
    id: 42,
    host: "localhost",
    port: 5432,
    database: "myapp"
  ))

  echo "1. Checkout connection from pool..."
  let conn = pooledConn.checkout()

  echo "\n2. Execute some queries..."
  let conn2 = conn.execute("SELECT * FROM users WHERE id = 1")
  let conn3 = conn2.execute("UPDATE users SET last_login = NOW() WHERE id = 1")

  echo "\n3. Start a transaction for batch insert..."
  let tx = conn3.beginTransaction()

  echo "\n4. Execute transactional queries..."
  let tx2 = tx.execute("INSERT INTO audit_log VALUES (1, 'login', NOW())")
  let tx3 = tx2.execute("INSERT INTO sessions VALUES (1, 'abc123', NOW())")

  echo "\n5. Commit the transaction..."
  let afterTx = tx3.commit()

  echo "\n6. Return connection to pool..."
  let returned = afterTx.release()

  echo "\n=== Connection lifecycle complete! ===\n"

  # =========================================================================
  # COMPILE-TIME ERRORS - These bugs are prevented:
  # =========================================================================

  echo "The following bugs are caught at COMPILE TIME:\n"

  # BUG 1: Query on pooled (not checked out) connection
  # let bad1 = returned.execute("SELECT 1")
  echo "  [PREVENTED] execute() on Pooled connection"

  # BUG 2: Return connection while in transaction
  # let bad2 = tx.release()
  echo "  [PREVENTED] release() on InTransaction connection"

  # BUG 3: Commit without starting transaction
  # let bad3 = conn.commit()
  echo "  [PREVENTED] commit() on CheckedOut connection (no transaction)"

  # BUG 4: Double checkout (already checked out)
  # let bad4 = conn.checkout()
  echo "  [PREVENTED] checkout() on CheckedOut connection"

  # BUG 5: Begin transaction inside transaction
  # let bad5 = tx.beginTransaction()
  echo "  [PREVENTED] beginTransaction() on InTransaction connection"

  echo "\nUncomment any of the 'bad' lines above to see the compile error!"
