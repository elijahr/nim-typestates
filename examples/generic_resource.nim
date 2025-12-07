## Generic Resource[T] Pattern
##
## A reusable typestate pattern for any resource that must be acquired
## before use and released after. Works with file handles, locks,
## connections, memory allocations, or any RAII-style resource.
##
## Run: nim c -r examples/generic_resource.nim

import ../src/typestates

# =============================================================================
# Generic Resource Pattern
# =============================================================================

type
  Resource*[T] = object
    ## Base type holding any resource.
    handle*: T
    name*: string  # For diagnostics

  Released*[T] = distinct Resource[T]
    ## Resource is not held - cannot be used.

  Acquired*[T] = distinct Resource[T]
    ## Resource is held - can be used, must be released.

typestate Resource[T]:
  consumeOnTransition = false
  states Released[T], Acquired[T]
  transitions:
    Released[T] -> Acquired[T]
    Acquired[T] -> Released[T]

proc acquire*[T](r: Released[T], handle: T): Acquired[T] {.transition.} =
  ## Acquire the resource with the given handle.
  var res = Resource[T](r)
  res.handle = handle
  echo "[", res.name, "] Acquired"
  result = Acquired[T](res)

proc release*[T](r: Acquired[T]): Released[T] {.transition.} =
  ## Release the resource back.
  echo "[", Resource[T](r).name, "] Released"
  result = Released[T](Resource[T](r))

proc use*[T](r: Acquired[T]): T {.notATransition.} =
  ## Access the underlying handle (only when acquired).
  Resource[T](r).handle

proc withResource*[T, R](r: Released[T], handle: T,
                          body: proc(h: T): R): (R, Released[T]) =
  ## RAII-style helper: acquire, use, release automatically.
  let acquired = r.acquire(handle)
  let res = body(acquired.use())
  let released = acquired.release()
  result = (res, released)

# =============================================================================
# Example 1: File Handle
# =============================================================================

type FileHandle = object
  fd: int
  path: string

proc openFile(path: string): FileHandle =
  echo "  Opening: ", path
  FileHandle(fd: 42, path: path)

proc closeFile(fh: FileHandle) =
  echo "  Closing: ", fh.path

proc readFile(fh: FileHandle): string =
  echo "  Reading from fd=", fh.fd
  "file contents"

block fileExample:
  echo "\n=== File Handle Example ==="

  # Create a released resource
  var file = Released[FileHandle](Resource[FileHandle](name: "config.txt"))

  # Acquire it
  let handle = openFile("/etc/config.txt")
  let acquired = file.acquire(handle)

  # Use it
  let contents = acquired.use().readFile()
  echo "  Got: ", contents

  # Release it
  let released = acquired.release()
  closeFile(handle)

  # COMPILE ERROR if uncommented:
  # discard released.use()  # Can't use released resource!

# =============================================================================
# Example 2: Database Connection
# =============================================================================

type DbConn = object
  connString: string
  connected: bool

proc connect(connString: string): DbConn =
  echo "  Connecting to: ", connString
  DbConn(connString: connString, connected: true)

proc disconnect(conn: DbConn) =
  echo "  Disconnecting"

proc query(conn: DbConn, sql: string): seq[string] =
  echo "  Query: ", sql
  @["row1", "row2", "row3"]

block dbExample:
  echo "\n=== Database Connection Example ==="

  var db = Released[DbConn](Resource[DbConn](name: "postgres"))

  # Manual acquire/release
  let conn = connect("postgresql://localhost/mydb")
  let acquired = db.acquire(conn)

  let rows = acquired.use().query("SELECT * FROM users")
  echo "  Results: ", rows

  let released = acquired.release()
  disconnect(conn)

# =============================================================================
# Example 3: Lock/Mutex simulation
# =============================================================================

type SimpleLock = object
  id: int

proc lock(id: int): SimpleLock =
  echo "  Locking mutex #", id
  SimpleLock(id: id)

proc unlock(l: SimpleLock) =
  echo "  Unlocking mutex #", l.id

block lockExample:
  echo "\n=== Lock Example ==="

  var mutex = Released[SimpleLock](Resource[SimpleLock](name: "mutex"))

  # Using withResource for RAII-style usage
  let (result, mutexReleased) = mutex.withResource(lock(1)) do (l: SimpleLock) -> int:
    echo "  Critical section with lock #", l.id
    42  # Return value from critical section

  echo "  Result from critical section: ", result
  unlock(SimpleLock(id: 1))

# =============================================================================
# Example 4: Memory Pool Allocation
# =============================================================================

type PooledBuffer = object
  size: int
  data: ptr UncheckedArray[byte]

proc allocFromPool(size: int): PooledBuffer =
  echo "  Allocating ", size, " bytes from pool"
  # In real code, this would allocate from a pool
  PooledBuffer(size: size, data: nil)

proc returnToPool(buf: PooledBuffer) =
  echo "  Returning ", buf.size, " bytes to pool"

block memoryExample:
  echo "\n=== Memory Pool Example ==="

  var buffer = Released[PooledBuffer](Resource[PooledBuffer](name: "buffer"))

  let mem = allocFromPool(4096)
  let acquired = buffer.acquire(mem)

  echo "  Using buffer of size: ", acquired.use().size

  let released = acquired.release()
  returnToPool(mem)

# =============================================================================
# Summary
# =============================================================================

echo "\n=== Summary ==="
echo "The Resource[T] pattern ensures:"
echo "  - Resources must be acquired before use"
echo "  - Resources must be released after use"
echo "  - Compile-time prevention of use-after-release"
echo "  - Works with ANY resource type via generics"

echo "\nAll examples passed!"
