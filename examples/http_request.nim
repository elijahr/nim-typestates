## HTTP Request Lifecycle with Typestates
##
## HTTP requests have a strict lifecycle that's easy to mess up:
## - Writing body after sending headers
## - Reading response before sending request
## - Sending headers twice
## - Using a connection after it's closed
##
## This example models the full request/response lifecycle.

import ../src/typestates

type
  HttpRequest = object
    meth: string
    path: string
    headers: seq[(string, string)]
    body: string
    responseCode: int
    responseBody: string

  # Request states
  Building = distinct HttpRequest      ## Accumulating headers
  HeadersSent = distinct HttpRequest   ## Headers sent, can send body
  RequestSent = distinct HttpRequest   ## Full request sent, awaiting response
  ResponseReceived = distinct HttpRequest  ## Response received, can read
  Closed = distinct HttpRequest        ## Connection closed

typestate HttpRequest:
  consumeOnTransition = false
  states Building, HeadersSent, RequestSent, ResponseReceived, Closed
  transitions:
    Building -> HeadersSent
    HeadersSent -> RequestSent         # Send body/finalize request
    RequestSent -> ResponseReceived    # Receive response
    ResponseReceived -> Closed | Building as ResponseAction  # Close or reuse for keep-alive
    * -> Closed                        # Can always abort

# ============================================================================
# Building the request
# ============================================================================

proc newRequest(meth: string, path: string): Building =
  ## Create a new HTTP request builder.
  echo "  [HTTP] ", meth, " ", path
  result = Building(HttpRequest(meth: meth, path: path))

proc header(req: Building, key: string, value: string): Building {.notATransition.} =
  ## Add a header to the request.
  var r = req.HttpRequest
  r.headers.add((key, value))
  echo "  [HTTP] Header: ", key, ": ", value
  result = Building(r)

proc sendHeaders(req: Building): HeadersSent {.transition.} =
  ## Finalize and send the headers.
  echo "  [HTTP] >>> Sending headers..."
  result = HeadersSent(req.HttpRequest)

# ============================================================================
# Sending the request
# ============================================================================

proc sendBody(req: HeadersSent, body: string): RequestSent {.transition.} =
  ## Send the request body (for POST, PUT, etc.).
  var r = req.HttpRequest
  r.body = body
  echo "  [HTTP] >>> Sending body (", body.len, " bytes)"
  result = RequestSent(r)

proc finish(req: HeadersSent): RequestSent {.transition.} =
  ## Finish request without body (for GET, DELETE, etc.).
  echo "  [HTTP] >>> Request complete (no body)"
  result = RequestSent(req.HttpRequest)

# ============================================================================
# Receiving the response
# ============================================================================

proc awaitResponse(req: RequestSent): ResponseReceived {.transition.} =
  ## Wait for and receive the response.
  var r = req.HttpRequest
  # Simulate response
  r.responseCode = 200
  r.responseBody = """{"status": "ok", "data": [1, 2, 3]}"""
  echo "  [HTTP] <<< Response: ", r.responseCode
  result = ResponseReceived(r)

func statusCode(resp: ResponseReceived): int =
  ## Get the HTTP status code.
  resp.HttpRequest.responseCode

func body(resp: ResponseReceived): string =
  ## Get the response body.
  resp.HttpRequest.responseBody

func isSuccess(resp: ResponseReceived): bool =
  ## Check if response indicates success (2xx).
  let code = resp.HttpRequest.responseCode
  code >= 200 and code < 300

# ============================================================================
# Closing or reusing
# ============================================================================

proc close(resp: ResponseReceived): Closed {.transition.} =
  ## Close the connection.
  echo "  [HTTP] Connection closed"
  result = Closed(resp.HttpRequest)

proc reuse(resp: ResponseReceived): Building {.transition.} =
  ## Reuse connection for another request (keep-alive).
  echo "  [HTTP] Reusing connection (keep-alive)"
  var r = HttpRequest()  # Fresh request on same connection
  result = Building(r)

# ============================================================================
# Example Usage
# ============================================================================

when isMainModule:
  echo "=== HTTP Request Demo ===\n"

  echo "1. Building GET request..."
  let req1 = newRequest("GET", "/api/users")
    .header("Accept", "application/json")
    .header("Authorization", "Bearer token123")

  echo "\n2. Sending headers..."
  let headersSent = req1.sendHeaders()

  echo "\n3. Finishing request (no body for GET)..."
  let sent = headersSent.finish()

  echo "\n4. Awaiting response..."
  let response = sent.awaitResponse()

  echo "\n5. Reading response..."
  echo "   Status: ", response.statusCode()
  echo "   Body: ", response.body()
  echo "   Success: ", response.isSuccess()

  echo "\n6. Closing connection..."
  let closed = response.close()

  echo "\n=== Request lifecycle complete! ===\n"

  # =========================================================================
  # COMPILE-TIME ERRORS - These bugs are prevented:
  # =========================================================================

  echo "The following bugs are caught at COMPILE TIME:\n"

  # BUG 1: Adding headers after they're sent
  # let bad1 = headersSent.header("X-Late", "header")
  echo "  [PREVENTED] header() after sendHeaders()"

  # BUG 2: Sending body on GET (before sending headers)
  # let bad2 = req1.sendBody("data")
  echo "  [PREVENTED] sendBody() before sendHeaders()"

  # BUG 3: Reading response before request is sent
  # let bad3 = headersSent.statusCode()
  echo "  [PREVENTED] statusCode() before response received"

  # BUG 4: Sending more data after request is complete
  # let bad4 = sent.sendBody("more data")
  echo "  [PREVENTED] sendBody() after request sent"

  # BUG 5: Using closed connection
  # let bad5 = closed.reuse()
  echo "  [PREVENTED] reuse() on Closed connection"

  echo "\nUncomment any of the 'bad' lines above to see the compile error!"
